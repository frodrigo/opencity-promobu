require 'yaml'
require 'json'
require 'shellwords'

module RulesLoader

  # Load a RulesSet from a YAML file.
  # The caller must have already included all the DSL modules (Rules, Shapes,
  # Faces, Snaps) so that the constants are accessible in the top-level
  # namespace — the same requirement as writing the rules in Ruby directly.
  #
  # Usage:
  #   require_relative 'promobu/rules_loader'
  #   rules = RulesLoader.load("rules/canary.yml")
  #   rules.apply([root_node])
  #
  def self.load( path )
    doc      = YAML.load_file( path, symbolize_names: true )
    check_keys!( doc, %i[rules textures sprite_atlas], "document root" )

    # Auto-detect sprite atlas based on rule file name, or use explicit config
    atlas_config = infer_sprite_atlas( path, doc[:sprite_atlas] )

    textures = build_textures( doc[:textures] || {}, atlas_config )
    rs       = RulesSet.new
    ( doc[:rules] || [] ).each { |r| rs << build_rule( r, textures, atlas_config ) }
    rs
  end

  def self.infer_sprite_atlas( rule_path, explicit_config )
    return explicit_config if explicit_config.is_a?(Hash)

    # Auto-detect: rules/canary.yml → rules/canary-sprites.{webp,json}
    dir = File.dirname( rule_path )
    base = File.basename( rule_path, '.yml' )
    sprite_webp = File.join( dir, "#{base}-sprites.webp" )
    sprite_json = File.join( dir, "#{base}-sprites.json" )

    { file: sprite_webp, sprites: sprite_json }
  end
  private_class_method :infer_sprite_atlas

  # ── private helpers ────────────────────────────────────────────────────────

  # Raise if +hash+ contains keys outside +allowed+.
  def self.check_keys!( hash, allowed, context )
    unknown = hash.keys - allowed
    raise "Unknown key(s) #{unknown.map(&:inspect).join(', ')} in #{context}" unless unknown.empty?
  end
  private_class_method :check_keys!

  def self.build_textures( map, atlas_config )
    map.transform_values { |t|
      # If it's a string, treat it as a sprite name
      if t.is_a?(String) || t.is_a?(Symbol)
        build_sprite_texture( t.to_s, atlas_config )
      else
        # Otherwise it's a hash config
        check_keys!( t, %i[type file sx sy double_side sprites sprite atlas_w atlas_h], "texture" )
        build_texture_object( t, atlas_config )
      end
    }
  end
  private_class_method :build_textures

  def self.build_sprite_texture( sprite_name, atlas_config )
    # Create a sprite texture from just the sprite name, using auto-detected atlas
    tex = AdaptedTexture.new( atlas_config[:file].to_s )
    apply_sprite_frame!( tex, {
      file: atlas_config[:file],
      sprites: atlas_config[:sprites],
      sprite: sprite_name
    } )
    tex
  end
  private_class_method :build_sprite_texture

  def self.build_texture_object( t, atlas_config = {} )
    case t[:type].to_s
    when 'tiled'
      tex = TiledTexture.new( t[:file].to_s, t[:sx].to_f, t[:sy].to_f )
      tex.double_side = true if t[:double_side]
      apply_sprite_frame!( tex, t ) if t[:sprites] || t[:sprite] || (t[:sprite_name])
      tex
    when 'adapted'
      tex = AdaptedTexture.new( t[:file].to_s )
      tex.double_side = true if t[:double_side]
      apply_sprite_frame!( tex, t ) if t[:sprites] || t[:sprite] || t[:sprite_name]
      tex
    when 'sprite'
      tex = AdaptedTexture.new( t[:file].to_s )
      tex.double_side = true if t[:double_side]
      apply_sprite_frame!( tex, t )
      tex
    else
      raise "Unknown texture type: #{t[:type].inspect}"
    end
  end
  private_class_method :build_texture_object

  SPRITE_JSON_CACHE = {}

  def self.apply_sprite_frame!( texture, t )
    sprites_path = t[:sprites].to_s
    sprite_name = t[:sprite].to_s

    raise "Sprite texture missing :sprites JSON path" if sprites_path.empty?
    raise "Sprite texture missing :sprite name" if sprite_name.empty?

    sprites = load_sprite_json( sprites_path )
    frame = sprites[sprite_name]
    raise "Sprite '#{sprite_name}' not found in #{sprites_path}" if frame.nil?

    atlas_w = t[:atlas_w]&.to_f
    atlas_h = t[:atlas_h]&.to_f
    if atlas_w.nil? || atlas_h.nil? || atlas_w <= 0 || atlas_h <= 0
      atlas_w, atlas_h = probe_image_size( t[:file].to_s ) || infer_atlas_size( sprites )
    end
    texture.sprite_frame = {
      x: frame.fetch('x').to_f,
      y: frame.fetch('y').to_f,
      w: frame.fetch('w').to_f,
      h: frame.fetch('h').to_f,
      atlas_w: atlas_w,
      atlas_h: atlas_h,
      repeat_x: !!frame['repeat_x']
    }
  end
  private_class_method :apply_sprite_frame!

  def self.probe_image_size( path )
    return nil if path.nil? || path.empty? || !File.exist?( path )

    if system( 'which identify > /dev/null 2>&1' )
      out = `identify -format "%w %h" #{Shellwords.escape(path)} 2>/dev/null`.strip
      if out =~ /\A(\d+)\s+(\d+)\z/
        return [Regexp.last_match(1).to_f, Regexp.last_match(2).to_f]
      end
    end

    if system( 'which magick > /dev/null 2>&1' )
      out = `magick identify -format "%w %h" #{Shellwords.escape(path)} 2>/dev/null`.strip
      if out =~ /\A(\d+)\s+(\d+)\z/
        return [Regexp.last_match(1).to_f, Regexp.last_match(2).to_f]
      end
    end

    nil
  end
  private_class_method :probe_image_size

  def self.load_sprite_json( path )
    SPRITE_JSON_CACHE[path] ||= begin
      json = JSON.parse( File.read( path ) )
      raise "Invalid sprite JSON root in #{path}: expected object" unless json.is_a?(Hash)
      json
    end
  rescue Errno::ENOENT
    raise "Sprite JSON not found: #{path}"
  rescue JSON::ParserError => e
    raise "Invalid sprite JSON #{path}: #{e.message}"
  end
  private_class_method :load_sprite_json

  def self.infer_atlas_size( sprites )
    max_x = 0.0
    max_y = 0.0

    sprites.each_value do |frame|
      next unless frame.is_a?(Hash)

      x = frame.fetch('x').to_f
      y = frame.fetch('y').to_f
      w = frame.fetch('w').to_f
      h = frame.fetch('h').to_f
      max_x = [max_x, x + w].max
      max_y = [max_y, y + h].max
    end

    [max_x, max_y]
  end
  private_class_method :infer_atlas_size

  def self.build_rule( r, textures, atlas_config = {} )
    check_keys!( r, %i[name condition actions], "rule '#{r[:name]}'" )
    cond    = build_condition( r[:condition] )
    actions = ( r[:actions] || [] ).flat_map { |a| build_action( a, textures, atlas_config ) }
    Rule.new( r[:name].to_s, cond, actions )
  end
  private_class_method :build_rule

  # Conditions ---------------------------------------------------------------

  def self.build_condition( c )
    return nil if c.nil?
    case c
    when 'front_face'
      proc { |node| node.queryAbsRotation?( V3._0 ) }
    when 'first'
      proc { |node| node.repeat_index == 0 }
    when 'last'
      proc { |node| !node.repeat_count.nil? && node.repeat_index == node.repeat_count - 1 }
    when 'not_first'
      proc { |node| !node.repeat_index.nil? && node.repeat_index > 0 }
    when 'not_last'
      proc { |node| !node.repeat_count.nil? && node.repeat_index < node.repeat_count - 1 }
    when Hash
      check_keys!( c, %i[scope_min], "condition" )
      if c[:scope_min]
        s = c[:scope_min]
        check_keys!( s, %i[x y], "scope_min condition" )
        x_min = ( s[:x] || 0 ).to_f
        y_min = ( s[:y] || 0 ).to_f
        proc { |node| node.shape.scope.x >= x_min && node.shape.scope.y >= y_min }
      else
        raise "Unrecognised condition hash: #{c.inspect}"
      end
    else
      raise "Unrecognised condition: #{c.inspect}"
    end
  end
  private_class_method :build_condition

  # Actions ------------------------------------------------------------------

  FACE_MAP = {
    'all'           => AllFaces,
    'top'           => TopFace,
    'bottom'        => BottomFace,
    'side'          => SideFaces,
    'right'         => RightFace,
    'left'          => LeftFace,
    'front'         => FrontFace,
    'back'          => BackFace,
    'main'          => MainFaces,
    'reverse-front'  => ReverseFrontFace,
    'reverse-back'   => ReverseBackFace,
    'reverse-left'   => ReverseLeftFace,
    'reverse-right'  => ReverseRightFace,
    'reverse-top'    => ReverseTopFace,
    'reverse-bottom' => ReverseBottomFace,
    'reverse-side'   => ReverseSideFaces,
    'reverse-all'    => ReverseAllFaces,
  }.freeze

  AXIS_MAP = {
    'x' => XAxis,
    'y' => YAxis,
    'z' => ZAxis,
  }.freeze

  SHAPE_MAP = {
    'Empty'    => -> { Empty    },
    'Box'      => -> { Box      },
    'Cylinder' => -> { Cylinder },
  }.freeze

  def self.build_action( hash, textures, atlas_config = {} )
    key   = hash.keys.first
    value = hash[key]

    case key
    when :split_x, :split_y, :split_z
      axis = AXIS_MAP.fetch( key.to_s[-1] ) { raise "Unknown axis in action key: #{key}" }
      raise "#{key} value must be a list" unless value.is_a?(Array)
      [ Split.new( axis, build_split_element( value, textures, atlas_config ) ) ]

    when :component
      check_keys!( value, %i[faces rules condition], "component action" )
      face_cls = FACE_MAP.fetch( value[:faces].to_s ) {
        raise "Unknown face selector: #{value[:faces].inspect}"
      }
      cond = value[:condition] ? build_condition( value[:condition].to_s ) : nil
      [ Component.new( face_cls, value[:rules].map(&:to_s), cond ) ]

    when :i
      [ I.new( value.to_s ) ]

    when :roof
      check_keys!( value, %i[type rule], "roof action" )
      roof_type = case value[:type].to_s
                  when 'gabled' then GabledRoof
                  else raise "Unknown roof type: #{value[:type].inspect}"
                  end
      [ Roof.new( roof_type, value[:rule].to_s ) ]

    when :instantiate
      shape_name, rule_ref = value
      shape_cls = SHAPE_MAP.fetch( shape_name.to_s ) {
        raise "Unknown shape: #{shape_name.inspect}"
      }.call
      rule_id = if rule_ref.is_a?(Hash)
        check_keys!( rule_ref, %i[condition actions], "anonymous instantiate rule" )
        cond    = build_condition( rule_ref[:condition] )
        actions = ( rule_ref[:actions] || [] ).flat_map { |a| build_action( a, textures, atlas_config ) }
        Rule.new( nil, cond, actions )
      else
        rule_ref
      end
      [ Instantiate.new( shape_cls, rule_id ) ]

    when :scope
      check_keys!( value, %i[x y z dx dy dz], "scope action" )
      [ build_scope( value ) ]

    when :translation
      check_keys!( value, %i[x y z], "translation action" )
      v = value
      [ Translation.new( V3[ (v[:x] || 0).to_f, (v[:y] || 0).to_f, (v[:z] || 0).to_f ] ) ]

    when :sub_context
      inner = value.flat_map { |a| build_action( a, textures, atlas_config ) }
      [ SubContext.new( inner ) ]

    when :texture
      tex = resolve_texture( value, textures, atlas_config )
      [ BindTexture.new( tex ) ]

    else
      raise "Unknown action key: #{key.inspect}"
    end
  end
  private_class_method :build_action

  # Named delta operations for scope: expressions.
  # Each proc receives the current scope and returns a Float delta.
  SCOPE_DELTA_OPS = {
    'neg_rand_half_y' => proc { |scope| -rand( scope.y / 2.0 ) },
  }.freeze

  # Build a Scope ContextEdit from a YAML hash.
  # Keys dx/dy/dz → add deltas to the current scope (values are numbers or token strings).
  # Keys x/y/z   → replace those components (omitted components keep their scope value).
  def self.build_scope( s )
    if s.key?(:dx) || s.key?(:dy) || s.key?(:dz)
      dx = s[:dx] || 0
      dy = s[:dy] || 0
      dz = s[:dz] || 0
      Scope.new( proc { |scope|
        V3[
          scope.x + resolve_scope_delta( dx, scope ),
          scope.y + resolve_scope_delta( dy, scope ),
          scope.z + resolve_scope_delta( dz, scope )
        ]
      })
    else
      x_lit = s[:x]&.to_f
      y_lit = s[:y]&.to_f
      z_lit = s[:z]&.to_f
      Scope.new( proc { |scope| V3[ x_lit || scope.x, y_lit || scope.y, z_lit || scope.z ] })
    end
  end
  private_class_method :build_scope

  def self.resolve_scope_delta( val, scope )
    case val
    when Numeric       then val.to_f
    when String, Symbol
      op = SCOPE_DELTA_OPS[ val.to_s ] or raise "Unknown scope delta token: #{val.inspect}"
      op.call( scope )
    else
      raise "Invalid scope delta: #{val.inspect}"
    end
  end
  private_class_method :resolve_scope_delta

  def self.build_split_element( elements, textures, atlas_config = {} )
    parts = elements.map { |e|
      if e[:snap]
        check_keys!( e, %i[snap], "split element (snap)" )
        Snap.new( e[:snap][:name].to_s, e[:snap][:size].to_f )
      else
        check_keys!( e, %i[abs rel rule repeat condition], "split element" )
        size = e[:abs] ? AbsoluteSize.new( e[:abs].to_f ) : RelativeSize.new( (e[:rel] || 1).to_f )
        # The rule slot may be either a plain rule name or an inline SplitRepeat
        sub  = e[:repeat] ? build_split_repeat( e[:repeat], textures, atlas_config ) : e[:rule].to_s
        cond = e[:condition] ? build_condition( e[:condition].to_s ) : nil
        [ size, sub, cond ]
      end
    }
    SplitElement.new( parts )
  end
  private_class_method :build_split_element

  def self.build_split_repeat( r, textures = {}, atlas_config = {} )
    check_keys!( r, %i[size rule elements snap last], "split repeat" )
    snap = r[:snap] ? Snap.new( r[:snap][:name].to_s, r[:snap][:size].to_f ) : nil
    last = r[:last]&.to_s
    # The sub-componant may be a plain rule name or an inline SplitElement
    sub  = r[:elements] ? build_split_element( r[:elements], textures ) : r[:rule].to_s
    SplitRepeat.new( r[:size].to_f, sub, snap, last )
  end
  private_class_method :build_split_repeat

  def self.resolve_texture( value, textures, atlas_config = {} )
    case value
    when String, Symbol
      # First try to find it as a defined texture key
      sym = value.to_sym
      return textures[sym] if textures.key?(sym)

      # If not found, treat it as a sprite name and create on-the-fly
      build_sprite_texture( value.to_s, atlas_config )
    when Hash
      # If no type is specified but sprite is present, treat as simplified sprite format
      if !value.key?(:type) && value.key?(:sprite)
        check_keys!( value, %i[sprite double_side], "simplified sprite texture" )
        # Try to find the sprite in textures first, else treat as sprite name
        sprite_sym = value[:sprite].to_sym
        tex = if textures.key?(sprite_sym)
          textures[sprite_sym]
        else
          build_sprite_texture( value[:sprite].to_s, atlas_config )
        end
        # Create a copy of the texture with double_side set if needed
        tex_copy = tex.dup
        tex_copy.double_side = true if value[:double_side]
        tex_copy
      else
        check_keys!( value, %i[type file sx sy double_side sprites sprite atlas_w atlas_h], "texture action" )
        build_texture_object( value )
      end
    else
      raise "Invalid texture value: #{value.inspect}"
    end
  end
  private_class_method :resolve_texture

end
