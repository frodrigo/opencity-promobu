require 'yaml'

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
    check_keys!( doc, %i[rules textures], "document root" )
    textures = build_textures( doc[:textures] || {} )
    rs       = RulesSet.new
    ( doc[:rules] || [] ).each { |r| rs << build_rule( r, textures ) }
    rs
  end

  # ── private helpers ────────────────────────────────────────────────────────

  # Raise if +hash+ contains keys outside +allowed+.
  def self.check_keys!( hash, allowed, context )
    unknown = hash.keys - allowed
    raise "Unknown key(s) #{unknown.map(&:inspect).join(', ')} in #{context}" unless unknown.empty?
  end
  private_class_method :check_keys!

  def self.build_textures( map )
    map.transform_values { |t|
      check_keys!( t, %i[type file sx sy double_side], "texture" )
      case t[:type]
      when 'tiled'
        tex = TiledTexture.new( t[:file], t[:sx], t[:sy] )
        tex.double_side = true if t[:double_side]
        tex
      when 'adapted'
        tex = AdaptedTexture.new( t[:file] )
        tex.double_side = true if t[:double_side]
        tex
      else raise "Unknown texture type: #{t[:type].inspect} in rules YAML"
      end
    }
  end
  private_class_method :build_textures

  def self.build_rule( r, textures )
    check_keys!( r, %i[name condition actions], "rule '#{r[:name]}'" )
    cond    = build_condition( r[:condition] )
    actions = ( r[:actions] || [] ).flat_map { |a| build_action( a, textures ) }
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

  def self.build_action( hash, textures )
    key   = hash.keys.first
    value = hash[key]

    case key
    when :split_x, :split_y, :split_z
      axis = AXIS_MAP.fetch( key.to_s[-1] ) { raise "Unknown axis in action key: #{key}" }
      raise "#{key} value must be a list" unless value.is_a?(Array)
      [ Split.new( axis, build_split_element( value, textures ) ) ]

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
        actions = ( rule_ref[:actions] || [] ).flat_map { |a| build_action( a, textures ) }
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
      inner = value.flat_map { |a| build_action( a, textures ) }
      [ SubContext.new( inner ) ]

    when :texture
      [ BindTexture.new( resolve_texture( value, textures ) ) ]

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

  def self.build_split_element( elements, textures )
    parts = elements.map { |e|
      if e[:snap]
        check_keys!( e, %i[snap], "split element (snap)" )
        Snap.new( e[:snap][:name].to_s, e[:snap][:size].to_f )
      else
        check_keys!( e, %i[abs rel rule repeat condition], "split element" )
        size = e[:abs] ? AbsoluteSize.new( e[:abs].to_f ) : RelativeSize.new( (e[:rel] || 1).to_f )
        # The rule slot may be either a plain rule name or an inline SplitRepeat
        sub  = e[:repeat] ? build_split_repeat( e[:repeat], textures ) : e[:rule].to_s
        cond = e[:condition] ? build_condition( e[:condition].to_s ) : nil
        [ size, sub, cond ]
      end
    }
    SplitElement.new( parts )
  end
  private_class_method :build_split_element

  def self.build_split_repeat( r, textures = {} )
    check_keys!( r, %i[size rule elements snap last], "split repeat" )
    snap = r[:snap] ? Snap.new( r[:snap][:name].to_s, r[:snap][:size].to_f ) : nil
    last = r[:last]&.to_s
    # The sub-componant may be a plain rule name or an inline SplitElement
    sub  = r[:elements] ? build_split_element( r[:elements], textures ) : r[:rule].to_s
    SplitRepeat.new( r[:size].to_f, sub, snap, last )
  end
  private_class_method :build_split_repeat

  def self.resolve_texture( value, textures )
    case value
    when String, Symbol
      textures.fetch( value.to_sym ) {
        raise "Undefined texture key: #{value.inspect}"
      }
    when Hash
      check_keys!( value, %i[type file sx sy double_side], "texture action" )
      case value[:type].to_s
      when 'tiled'
        t = TiledTexture.new( value[:file].to_s, value[:sx].to_f, value[:sy].to_f )
        t.double_side = true if value[:double_side]
        t
      when 'adapted'
        t = AdaptedTexture.new( value[:file].to_s )
        t.double_side = true if value[:double_side]
        t
      else raise "Unknown texture type in action: #{value[:type].inspect}"
      end
    else
      raise "Invalid texture value: #{value.inspect}"
    end
  end
  private_class_method :resolve_texture

end
