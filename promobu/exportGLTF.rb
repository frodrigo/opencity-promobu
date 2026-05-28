require 'json'

# glTF 2.0 GLB exporter.
# Writes a single self-contained <base>.glb with all images embedded in the BIN chunk.
# Usage: ExportGLTF::export( root_node, "out.glb" )

module ExportGLTF

  def self.export( root, file_name )
    builder = GLTFBuilder.new
    root.buildGLTF( builder, scene_root: true )
    builder.write( file_name )
  end

  # ---------------------------------------------------------------------------
  # Accumulates all glTF structures and binary buffer data.
  # ---------------------------------------------------------------------------
  class GLTFBuilder

    def initialize
      @nodes        = []
      @meshes       = []
      @materials    = []
      @textures     = []
      @images       = []
      @samplers     = []
      @accessors    = []
      @buffer_views = []
      @bin          = ''.b    # binary buffer (ASCII-8BIT / little-endian)
      @mat_cache    = {}      # textureFile path | :default → material index
      @scene_nodes  = []      # indices of top-level scene nodes
    end

    def add_scene_node( idx )
      @scene_nodes << idx
    end

    # Create a glTF node; returns its index.
    def add_node( name, translation, quat, mesh_idx, children )
      h = { name: name }
      t = translation
      h[:translation] = [t.x, t.y, t.z]  if t.x != 0.0 || t.y != 0.0 || t.z != 0.0
      h[:rotation]    = quat              if quat != [0.0, 0.0, 0.0, 1.0]
      h[:mesh]        = mesh_idx          unless mesh_idx.nil?
      h[:children]    = children          unless children.empty?
      idx = @nodes.size
      @nodes << h
      idx
    end

    # Create a glTF mesh containing the given primitives; returns its index,
    # or nil if primitives is empty.
    def add_mesh( name, primitives )
      return nil if primitives.empty?
      idx = @meshes.size
      @meshes << { name: name, primitives: primitives }
      idx
    end

    # Build a primitive hash from caller-supplied geometry arrays.
    #   positions : [[x,y,z], ...]   – vertex positions
    #   uvs       : [[u,v],   ...]   – texture coordinates (V flipped: glTF origin = top-left)
    #   normals   : [[x,y,z], ...]   – per-vertex normals
    #   indices   : [i0, i1, ...]    – triangle indices (UINT16)
    #   mat_idx   : Integer          – material index
    def make_primitive( positions, uvs, normals, indices, mat_idx )
      {
        attributes: {
          POSITION:   push_vec3f( positions, 34962 ),
          TEXCOORD_0: push_vec2f( uvs,       34962 ),
          NORMAL:     push_vec3f( normals,   34962 )
        },
        indices:  push_u16( indices, 34963 ),
        material: mat_idx,
        mode:     4   # TRIANGLES
      }
    end

    # Return the material index for +texture+ (AdaptedTexture or TiledTexture),
    # creating a PBR material + texture + image + sampler on first use.
    # The image bytes are embedded in the BIN buffer.
    # Pass nil to get a plain grey default material.
    def material_for( texture )
      return default_material if texture.nil?
      key = texture.textureFile
      cache_key = [key, texture.double_side]
      @mat_cache[cache_key] ||= begin
        img  = embed_image( key )
        samp = push_to( @samplers, { wrapS: 10497, wrapT: 10497 } )  # REPEAT/REPEAT
        tex  = push_to( @textures, { sampler: samp, source: img } )
        mat = {
          name: key,
          pbrMetallicRoughness: {
            baseColorTexture: { index: tex },
            metallicFactor:   0.0,
            roughnessFactor:  1.0
          }
        }
        mat[:doubleSided] = true if texture.double_side
        push_to( @materials, mat )
      end
    end

    # Serialise to a single self-contained GLB file.
    # GLB layout: 12-byte file header | JSON chunk | BIN chunk
    def write( file_name )
      base = file_name.sub( /\.gl[bt]f?$/i, '' )

      doc = {
        asset:       { version: '2.0', generator: 'promobu' },
        scene:       0,
        scenes:      [{ nodes: @scene_nodes }],
        nodes:       @nodes,
        meshes:      non_empty( @meshes ),
        accessors:   non_empty( @accessors ),
        bufferViews: non_empty( @buffer_views ),
        buffers:     @bin.empty? ? nil : [{ byteLength: @bin.bytesize }],
        materials:   non_empty( @materials ),
        textures:    non_empty( @textures ),
        images:      non_empty( @images ),
        samplers:    non_empty( @samplers )
      }.compact

      # JSON chunk: pad to 4-byte alignment with spaces (0x20)
      json_str  = JSON.generate( doc )
      json_str += ' ' * ( ( 4 - json_str.bytesize % 4 ) % 4 )

      # BIN chunk: pad to 4-byte alignment with NUL bytes (0x00)
      bin_data  = @bin.dup
      bin_data += "\x00" * ( ( 4 - bin_data.bytesize % 4 ) % 4 ) unless bin_data.empty?

      total = 12 + 8 + json_str.bytesize
      total += 8 + bin_data.bytesize unless bin_data.empty?

      glb = ''.b
      glb << [ 0x46546C67, 2, total ].pack('V3')             # magic 'glTF', version, length
      glb << [ json_str.bytesize, 0x4E4F534A ].pack('V2')   # JSON chunk header
      glb << json_str.b
      unless bin_data.empty?
        glb << [ bin_data.bytesize, 0x004E4942 ].pack('V2') # BIN\0 chunk header
        glb << bin_data
      end

      File.binwrite( "#{base}.glb", glb )
    end

    private

    def default_material
      @mat_cache[:default] ||= push_to( @materials, {
        name: 'default',
        pbrMetallicRoughness: {
          baseColorFactor: [0.8, 0.8, 0.8, 1.0],
          metallicFactor:  0.0,
          roughnessFactor: 1.0
        }
      })
    end

    def push_to( arr, val )
      idx = arr.size; arr << val; idx
    end

    def non_empty( arr )
      arr.empty? ? nil : arr
    end

    # Pad binary buffer to 4-byte alignment (required by the glTF spec).
    def align4
      pad = ( 4 - @bin.bytesize % 4 ) % 4
      @bin << ( "\x00" * pad )
    end

    MIME_TYPES = {
      '.png'  => 'image/png',
      '.jpg'  => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif'  => 'image/gif',
      '.bmp'  => 'image/bmp',
    }.freeze

    # Read +path+ from disk and embed it as a bufferView in the BIN buffer.
    # Returns the image index. Falls back to a URI reference if the file is absent.
    def embed_image( path )
      mime = MIME_TYPES[ File.extname( path ).downcase ] || 'image/png'
      if File.exist?( path )
        data = File.binread( path )
        align4
        bv = push_to( @buffer_views, {
          buffer:     0,
          byteOffset: @bin.bytesize,
          byteLength: data.bytesize
          # no :target — image bufferViews must not carry a GPU buffer target
        })
        @bin << data
        push_to( @images, { bufferView: bv, mimeType: mime } )
      else
        # Image file not found at runtime; store a plain URI reference instead.
        push_to( @images, { uri: path } )
      end
    end

    # Pack [[x,y,z],...] as FLOAT32-LE; add bufferView + accessor.
    # Computes min/max (required for POSITION accessors by the spec).
    def push_vec3f( triples, target )
      flat  = triples.flatten
      count = flat.size / 3
      min_v = 3.times.map { |i| flat.each_slice(3).map { |s| s[i] }.min }
      max_v = 3.times.map { |i| flat.each_slice(3).map { |s| s[i] }.max }
      bv_accessor( flat.pack('e*'), target, 5126, 'VEC3', count, min: min_v, max: max_v )
    end

    # Pack [[u,v],...] as FLOAT32-LE; add bufferView + accessor.
    def push_vec2f( pairs, target )
      flat  = pairs.flatten
      count = flat.size / 2
      bv_accessor( flat.pack('e*'), target, 5126, 'VEC2', count )
    end

    # Pack [i,...] as UINT16-LE; add bufferView + accessor.
    def push_u16( vals, target )
      bv_accessor( vals.pack('v*'), target, 5123, 'SCALAR', vals.size )
    end

    def bv_accessor( packed, target, component_type, type, count, **extra )
      align4
      byte_offset = @bin.bytesize
      @bin << packed
      bv = push_to( @buffer_views, {
        buffer:     0,
        byteOffset: byte_offset,
        byteLength: packed.bytesize,
        target:     target
      })
      push_to( @accessors, {
        bufferView:    bv,
        byteOffset:    0,
        componentType: component_type,
        count:         count,
        type:          type
      }.merge( extra ) )
    end

  end  # GLTFBuilder

end  # ExportGLTF


# -----------------------------------------------------------------------------
# Node: build the glTF scene graph recursively.
# -----------------------------------------------------------------------------
module ProcedureBuildingGenerator
  class Node

    # Convert this node (and all descendants) into glTF nodes.
    # Call with scene_root: true for the root of the tree.
    def buildGLTF( builder, scene_root: false )
      # Convert Euler angles (degrees, XYZ-intrinsic order matching rotationMatrix)
      # to a unit quaternion [x, y, z, w] required by glTF.
      rx = rotation.x * Math::PI / 180.0
      ry = rotation.y * Math::PI / 180.0
      rz = rotation.z * Math::PI / 180.0
      cx, sx = Math.cos( rx / 2 ), Math.sin( rx / 2 )
      cy, sy = Math.cos( ry / 2 ), Math.sin( ry / 2 )
      cz, sz = Math.cos( rz / 2 ), Math.sin( rz / 2 )
      quat = [
        sx*cy*cz + cx*sy*sz,   # qx
        cx*sy*cz - sx*cy*sz,   # qy
        cx*cy*sz + sx*sy*cz,   # qz
        cx*cy*cz - sx*sy*sz    # qw
      ]

      # Leaf nodes with a shape become meshes.
      mesh_idx = nil
      if subNodes.empty? && !shape.nil?
        prims    = shape.buildGLTFPrimitives( builder )
        mesh_idx = builder.add_mesh( ruleId.to_s, prims )
      end

      children = subNodes.map { |child| child.buildGLTF( builder ) }
      idx = builder.add_node( ruleId.to_s, position, quat, mesh_idx, children )
      builder.add_scene_node( idx ) if scene_root
      idx
    end

  end
end


# -----------------------------------------------------------------------------
# Shape extensions: produce glTF triangle primitives.
#
# Coordinate conventions used throughout:
#   • A shape's local geometry lives in the XY-plane at Z = 0.
#   • Winding [0,2,1, 0,3,2] for a quad (v0..v3) yields a face normal in the
#     –Z direction: (v2−v0) × (v1−v0) ∝ (0, 0, −1).
#   • UV origin is top-left (glTF convention), so V is flipped relative to X3D:
#       glTF V = 1 − OpenGL V.
# -----------------------------------------------------------------------------
module Shapes

  # Shared quad winding: produces –Z normal for a quad lying in the XY plane.
  GLTF_QUAD_IDX = [0, 2, 1,  0, 3, 2].freeze

  class ::Shapes::Shape

    def gltf_map_uvs( base_uvs, shape_w=nil, shape_h=nil )
      return base_uvs if texture.nil?

      base_uvs.map { |u, v| texture.map_uv( u, v, shape_w, shape_h ) }
    end

    def buildGLTFPrimitives( builder )
      []
    end
  end

  class ::Shapes::Rectangle < Shape2D
    def buildGLTFPrimitives( builder )
      sx = scope.x.to_f
      sy = scope.y.to_f
      positions = [[0, 0, 0], [sx, 0, 0], [sx, sy, 0], [0, sy, 0]]
      uvs       = gltf_map_uvs([[0, 1], [1, 1], [1, 0], [0, 0]])
      normals   = Array.new(4) { [0, 0, -1] }
      mat = builder.material_for( texture )
      [ builder.make_primitive( positions, uvs, normals, GLTF_QUAD_IDX.dup, mat ) ]
    end
  end

  class ::Shapes::IsoscelesTriangle < Shape2D
    def buildGLTFPrimitives( builder )
      sx = scope.x.to_f
      sy = scope.y.to_f
      # Winding [0,2,1]: (v2−v0)×(v1−v0) = (sx/2,sy,0)×(sx,0,0) ∝ (0,0,−1)
      positions = [[0, 0, 0], [sx, 0, 0], [sx / 2.0, sy, 0]]
      uvs       = gltf_map_uvs([[0, 1], [1, 1], [0.5, 0]])
      normals   = Array.new(3) { [0, 0, -1] }
      mat = builder.material_for( texture )
      [ builder.make_primitive( positions, uvs, normals, [0, 2, 1], mat ) ]
    end
  end

  class ::Shapes::Box < Shape3D
    # Emit all 6 faces as a single primitive.
    # Each face uses GLTF_QUAD_IDX winding; vertex order chosen so the
    # cross product gives the correct outward normal for every face.
    def buildGLTFPrimitives( builder )
      sx = scope.x.to_f
      sy = scope.y.to_f
      sz = scope.z.to_f
      mat = builder.material_for( texture )
      positions = []; uvs = []; normals = []; indices = []
      face_quads( sx, sy, sz ).each do |verts, normal|
        base = positions.size
        verts.each { |v| positions << v }
        uvs     += gltf_map_uvs([[0, 1], [1, 1], [1, 0], [0, 0]])
        normals += [normal] * 4
        indices += GLTF_QUAD_IDX.map { |i| base + i }
      end
      [ builder.make_primitive( positions, uvs, normals, indices, mat ) ]
    end

    private

    # Returns [[verts_4x3, normal_3], ...] for all 6 faces.
    # Vertex ordering is chosen so that GLTF_QUAD_IDX = [0,2,1, 0,3,2] gives
    # the listed outward normal via (v2−v0) × (v1−v0).
    def face_quads( sx, sy, sz )
      [
        [ [[0,0,0],[sx,0,0],[sx,sy,0],[0,sy,0]],       [ 0, 0,-1] ],  # front  (−Z)
        [ [[sx,0,sz],[0,0,sz],[0,sy,sz],[sx,sy,sz]],   [ 0, 0, 1] ],  # back   (+Z)
        [ [[0,0,sz],[0,0,0],[0,sy,0],[0,sy,sz]],       [-1, 0, 0] ],  # left   (−X)
        [ [[sx,0,0],[sx,0,sz],[sx,sy,sz],[sx,sy,0]],   [ 1, 0, 0] ],  # right  (+X)
        [ [[0,0,0],[0,0,sz],[sx,0,sz],[sx,0,0]],       [ 0,-1, 0] ],  # bottom (−Y)
        [ [[0,sy,sz],[0,sy,0],[sx,sy,0],[sx,sy,sz]],   [ 0, 1, 0] ],  # top    (+Y)
      ]
    end
  end

  class ::Shapes::Cylinder < Shape3D
    # Build a polygonal cylinder/prism mesh aligned on Y.
    # The side surface is split into +segments+ planar panels (default 12).
    def buildGLTFPrimitives( builder )
      sx = scope.x.to_f
      sy = scope.y.to_f
      sz = scope.z.to_f
      return [] if sx <= 0.0 || sy <= 0.0 || sz <= 0.0

      segments = [ (self.segments || 12).to_i, 3 ].max
      cx = sx / 2.0
      cz = sz / 2.0
      rx = sx / 2.0
      rz = sz / 2.0

      positions = []
      uvs       = []
      normals   = []
      indices   = []

      ring = (0...segments).map do |i|
        t = (2.0 * Math::PI * i) / segments
        [ cx + rx * Math.cos(t), cz + rz * Math.sin(t), t ]
      end

      (0...segments).each do |i|
        x0, z0, a0 = ring[i]
        x1, z1, a1 = ring[(i + 1) % segments]
        base = positions.size
        positions += [[x0, 0.0, z0], [x1, 0.0, z1], [x1, sy, z1], [x0, sy, z0]]
        edge_len = Math.sqrt( (x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0) )
        uvs += gltf_map_uvs([[0, 1], [1, 1], [1, 0], [0, 0]], edge_len, sy)
        nx = Math.cos( (a0 + a1) / 2.0 )
        nz = Math.sin( (a0 + a1) / 2.0 )
        normals += [[nx, 0.0, nz]] * 4
        indices += GLTF_QUAD_IDX.map { |j| base + j }
      end

      top_center = positions.size
      positions << [cx, sy, cz]
      uvs << [0.5, 0.5]
      normals << [0.0, 1.0, 0.0]
      top_ring = ring.map do |x, z, _a|
        positions.size.tap do
          positions << [x, sy, z]
          uvs << [0.5 + (x - cx) / sx, 0.5 - (z - cz) / sz]
          normals << [0.0, 1.0, 0.0]
        end
      end
      (0...segments).each do |i|
        indices += [top_center, top_ring[(i + 1) % segments], top_ring[i]]
      end

      bottom_center = positions.size
      positions << [cx, 0.0, cz]
      uvs << [0.5, 0.5]
      normals << [0.0, -1.0, 0.0]
      bottom_ring = ring.map do |x, z, _a|
        positions.size.tap do
          positions << [x, 0.0, z]
          uvs << [0.5 + (x - cx) / sx, 0.5 - (z - cz) / sz]
          normals << [0.0, -1.0, 0.0]
        end
      end
      (0...segments).each do |i|
        indices += [bottom_center, bottom_ring[i], bottom_ring[(i + 1) % segments]]
      end

      mat = builder.material_for( texture )
      [ builder.make_primitive( positions, uvs, normals, indices, mat ) ]
    end
  end

  class ::Shapes::CylinderSide < Shape3D
    # Build only the lateral polygonal cylinder surface (no top/bottom caps).
    def buildGLTFPrimitives( builder )
      sx = scope.x.to_f
      sy = scope.y.to_f
      sz = scope.z.to_f
      return [] if sx <= 0.0 || sy <= 0.0 || sz <= 0.0

      segments = [ (self.segments || 12).to_i, 3 ].max
      cx = sx / 2.0
      cz = sz / 2.0
      rx = sx / 2.0
      rz = sz / 2.0

      positions = []
      uvs       = []
      normals   = []
      indices   = []

      ring = (0...segments).map do |i|
        t = (2.0 * Math::PI * i) / segments
        [ cx + rx * Math.cos(t), cz + rz * Math.sin(t), t ]
      end

      (0...segments).each do |i|
        x0, z0, a0 = ring[i]
        x1, z1, a1 = ring[(i + 1) % segments]
        base = positions.size
        positions += [[x0, 0.0, z0], [x1, 0.0, z1], [x1, sy, z1], [x0, sy, z0]]
        edge_len = Math.sqrt( (x1 - x0) * (x1 - x0) + (z1 - z0) * (z1 - z0) )
        uvs += gltf_map_uvs([[0, 1], [1, 1], [1, 0], [0, 0]], edge_len, sy)
        nx = Math.cos( (a0 + a1) / 2.0 )
        nz = Math.sin( (a0 + a1) / 2.0 )
        normals += [[nx, 0.0, nz]] * 4
        indices += GLTF_QUAD_IDX.map { |j| base + j }
      end

      mat = builder.material_for( texture )
      [ builder.make_primitive( positions, uvs, normals, indices, mat ) ]
    end
  end

  class ::Shapes::Cupola < Shape3D
    # Build a pointed cupola mesh aligned on Y.
    # The base is the same footprint as a cylinder, and the profile tapers to
    # a point at the top. The height is split into +levels+ stacked bands.
    def buildGLTFPrimitives( builder )
      emit_cupola_primitives( builder, bottom_cap: true )
    end

    private

    def cupola_levels
      [ (self.levels || 1).to_i, 1 ].max
    end

    def emit_cupola_primitives( builder, bottom_cap: )
      sx = scope.x.to_f
      sy = scope.y.to_f
      sz = scope.z.to_f
      return [] if sx <= 0.0 || sy <= 0.0 || sz <= 0.0

      segments = [ (self.segments || 12).to_i, 3 ].max
      levels   = cupola_levels
      level_h  = sy / levels.to_f
      cx = sx / 2.0
      cz = sz / 2.0
      rx = sx / 2.0
      rz = sz / 2.0

      positions = []
      uvs       = []
      normals   = []
      indices   = []

      ring_points = (0...segments).map do |i|
        t = (2.0 * Math::PI * i) / segments
        [ Math.cos(t), Math.sin(t), t ]
      end

      rings = (0..levels).map do |level|
        t = level / levels.to_f
        scale = Math.sqrt(1.0 - t * t)
        y = level * level_h
        ring_points.map { |cos_t, sin_t, a| [ cx + rx * scale * cos_t, y, cz + rz * scale * sin_t, a, scale ] }
      end

      (0...levels).each do |level|
        lower = rings[level]
        upper = rings[level + 1]
        (0...segments).each do |i|
          x0, y0, z0, a0, _s0 = lower[i]
          x1, y1, z1, a1, s1  = upper[i]
          x2, y2, z2, _a2, _s2 = upper[(i + 1) % segments]
          x3, y3, z3, _a3, _s3 = lower[(i + 1) % segments]

          if s1 > 0.0001
            base = positions.size
            positions += [[x0, y0, z0], [x3, y3, z3], [x2, y2, z2], [x1, y1, z1]]
            edge_len = Math.sqrt( (x3 - x0) * (x3 - x0) + (z3 - z0) * (z3 - z0) )
            uvs += gltf_map_uvs([[0, 1], [1, 1], [1, 0], [0, 0]], edge_len, level_h)
            nx = Math.cos( (a0 + a1) / 2.0 )
            nz = Math.sin( (a0 + a1) / 2.0 )
            normals += [[nx, 0.0, nz]] * 4
            indices += GLTF_QUAD_IDX.map { |j| base + j }
          else
            apex = [ cx, sy, cz ]
            base = positions.size
            positions += [[x0, y0, z0], [x3, y3, z3], apex]
            edge_len = Math.sqrt( (x3 - x0) * (x3 - x0) + (z3 - z0) * (z3 - z0) )
            uvs += gltf_map_uvs([[0, 1], [1, 1], [0.5, 0]], edge_len, level_h)
            nx = Math.cos( (a0 + a1) / 2.0 )
            nz = Math.sin( (a0 + a1) / 2.0 )
            normals += [[nx, 0.0, nz], [nx, 0.0, nz], [0.0, 1.0, 0.0]]
            indices += [base, base + 2, base + 1]
          end
        end
      end

      if bottom_cap
        bottom_center = positions.size
        positions << [cx, 0.0, cz]
        uvs << [0.5, 0.5]
        normals << [0.0, -1.0, 0.0]
        bottom_ring = rings.first.map do |x, y, z, _a, _s|
          positions.size.tap do
            positions << [x, y, z]
            uvs << [0.5 + (x - cx) / sx, 0.5 - (z - cz) / sz]
            normals << [0.0, -1.0, 0.0]
          end
        end
        (0...segments).each do |i|
          indices += [bottom_center, bottom_ring[i], bottom_ring[(i + 1) % segments]]
        end
      end

      mat = builder.material_for( texture )
      [ builder.make_primitive( positions, uvs, normals, indices, mat ) ]
    end
  end

  class ::Shapes::CupolaSide < Cupola
    # Build only the pointed cupola side surface (no bottom cap).
    def buildGLTFPrimitives( builder )
      emit_cupola_primitives( builder, bottom_cap: false )
    end
  end

end
