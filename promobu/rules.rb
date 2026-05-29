
module Rules

	class Rule
		attr_accessor :id, :condition, :generativeParts, :probability

		def initialize( id, condition, generativeParts, probability=1 )
			self.id = id
			self.condition = condition
			self.generativeParts = generativeParts
			self.probability = probability
		end

		def apply?( node )
			condition.nil? || condition.call( node )
		end

		def apply( node )
			generate( node, self.generativeParts, V3._0, V3._0, node.shape.scope )
		end

		private

		def generate( node, generativeParts, position, rotation, scope )
			result = []
			generativeParts.each { |gp|
				case gp
				when ContextEdit
					position, rotation, scope = gp.apply( position, rotation, scope )
				when Creational
					result << gp.apply( node, position, rotation, scope )
				when SubContext
					result.concat( generate( node, gp.generativeParts, position, rotation, scope ) )
				when SubNodeGenerator
					result.concat( gp.apply( node, node.shape, position, rotation, scope ) )
				when BindTexture
					gp.apply( node.shape )
				end
			}
			result
		end
	end

	class GenerativePart
		def apply
		end
	end

	class SubContext < GenerativePart
		attr_accessor :generativeParts

		def initialize( generativeParts )
			self.generativeParts = generativeParts
		end
	end

	class ContextEdit < GenerativePart
		attr_accessor :v3

		def initialize( v3 )
			self.v3 = v3
		end

		def apply( position, rotation, scope )
			[ position, rotation, scope ]
		end
	end

	class Translation < ContextEdit
		def apply( position, rotation, scope )
			[ position+v3, rotation, scope ]
		end
	end

	class Rotation < ContextEdit
		def apply( position, rotation, scope )
			[ position, rotation+v3, scope ]
		end
	end

	class Scope < ContextEdit
		def apply( position, rotation, scope )
			if v3.is_a?(Proc)
				[ position, rotation, v3.call(scope) ]
			else
				[ position, rotation, scope+v3 ]
			end
		end
	end

	class SubNodeGenerator < GenerativePart
		def apply( node, shape, position=V3._0, rotation=V3._0, scope=nil )
			[]
		end
	end

	class Component < SubNodeGenerator
		attr_accessor :splitType, :ids, :condition

		def initialize( splitType, ids, condition=nil )
			self.splitType = splitType
			self.ids = ids
			self.condition = condition
		end

		def apply( node, shape, position=V3._0, rotation=V3._0, scope=nil )
			return [] if condition && !condition.call( node )
			effective_shape = scope.nil? || scope.equal?(shape.scope) ? shape : (s = shape.clone; s.scope = scope; s)
			components = effective_shape.component( splitType )
			return [] if components.nil?
			subNode = []
			ids_local = ids.dup
			id = nil
			components.each{ |subShapeArray|
				if ids_local.length >= 1
					id = ids_local.shift
				end
				subNode << Node.new( node, id, subShapeArray[2], position + subShapeArray[0], rotation + subShapeArray[1] )
			}
			subNode
		end
	end

	class ::Rules::SplitComponant
		private

		def register_snap_plane( node, subShapeArray )
			(abs_position, abs_rotation) = node.toAbs( subShapeArray[0], subShapeArray[1] )
			SnapRegistery.instance << SnapPlane.new( subShapeArray[2].snap, abs_position, abs_rotation )
		end
	end

	class SplitElement < SplitComponant
		attr_accessor :parts, :snapGroup

		def initialize( parts, snapGroup=nil )
			self.parts = parts
			self.snapGroup = snapGroup
		end

		def apply( axis, node, shape )
			subNode = []
			# Filter out parts whose condition fails for the current node
			active_parts = parts.select { |p| !p.is_a?(Array) || p[2].nil? || p[2].call(node) }
			partSizes = active_parts.map { |x| x.is_a?(Array) ? x[0] : x }
			partIds   = active_parts.map { |x| x.is_a?(Array) ? x[1] : x }
			shape.split( node, axis, partSizes, snapGroup ).each{ |subShapeArray|
				id = partIds.shift
				if subShapeArray[2].is_a?(SnapPlaneRectangle)
					register_snap_plane( node, subShapeArray )
				elsif id.is_a?(SplitComponant)
					subNode.concat( id.apply( axis, node, subShapeArray[2] ).collect{ |nodeComponent|
						Node.new( node, nodeComponent.ruleId, nodeComponent.shape, nodeComponent.position+subShapeArray[0], nodeComponent.rotation+subShapeArray[1] )
					} )
				else
					subNode << Node.new( node, id, subShapeArray[2], subShapeArray[0], subShapeArray[1] )
				end
			}
			subNode
		end
	end

	class SplitRepeat < SplitComponant
		attr_accessor :tileSize, :splitComponant, :snapPlane, :snapGroup

		def initialize( tileSize, splitComponant, snapPlane=nil, snapGroup=nil )
			self.tileSize = tileSize
			self.splitComponant = splitComponant
			self.snapPlane = snapPlane
			self.snapGroup = snapGroup
		end

		def apply( axis, node, shape )
			subNode   = []
			saved_ri  = node.repeat_index
			saved_rc  = node.repeat_count
			length    = Float( axis.component( shape.scope ) )
			nbTiles   = ( length / Float(tileSize) ).floor
			return subNode if nbTiles <= 0

			# --- Variable-size tiling when splitComponant is a SplitElement -------
			# For each tile, determine which parts survive their conditions, then
			# compute the effective tile size:
			#   • tiles with surviving rel parts  → share the remaining length equally
			#   • tiles with abs parts only       → shrink to sum of abs sizes
			# This recomputation happens here (repeat level), not inside SplitElement.
			tile_sizes = if splitComponant.is_a?(SplitElement)
				tile_info = (0...nbTiles).map { |i|
					node.repeat_index = i
					node.repeat_count = nbTiles
					active  = splitComponant.parts.select { |p|
						!p.is_a?(Array) || p[2].nil? || p[2].call(node)
					}
					abs_sum = active.sum { |p|
						(p.is_a?(Array) && p[0].is_a?(AbsoluteSize)) ? p[0].value : 0.0
					}
					rel_sum = active.sum { |p|
						(p.is_a?(Array) && p[0].is_a?(RelativeSize)) ? p[0].value : 0.0
					}
					{ abs_sum: abs_sum, rel_sum: rel_sum }
				}
				total_abs = tile_info.sum { |t| t[:abs_sum] }
				total_rel = tile_info.sum { |t| t[:rel_sum] }
				r = total_rel > 0 ? ( length - total_abs ) / total_rel : 0.0
				tile_info.map { |t| t[:abs_sum] + t[:rel_sum] * r }
			else
				# No conditional parts — keep uniform tiling (exact fill)
				adj = length / nbTiles
				Array.new( nbTiles, adj )
			end

			# Split the shape into variable-sized tile sub-shapes
			part_sizes = tile_sizes.map { |s| AbsoluteSize.new(s) }
			tile_shapes = shape.split( node, axis, part_sizes, snapGroup )
			tile_count  = tile_shapes.count { |s| !s[2].is_a?(SnapPlaneRectangle) }
			tile_idx    = 0

			tile_shapes.each { |subShapeArray|
				if subShapeArray[2].is_a?(SnapPlaneRectangle)
					register_snap_plane( node, subShapeArray )
				elsif splitComponant.is_a?(SplitComponant)
					node.repeat_index = tile_idx
					node.repeat_count = tile_count
					new_nodes = splitComponant.apply( axis, node, subShapeArray[2] ).collect { |nodeComponent|
						Node.new( node, nodeComponent.ruleId, nodeComponent.shape, nodeComponent.position+subShapeArray[0], nodeComponent.rotation+subShapeArray[1] )
					}
					new_nodes.each { |n| n.repeat_index = tile_idx; n.repeat_count = tile_count }
					subNode.concat( new_nodes )
					tile_idx += 1
				else
					n = Node.new( node, splitComponant, subShapeArray[2], subShapeArray[0], subShapeArray[1] )
					n.repeat_index = tile_idx
					n.repeat_count = tile_count
					subNode << n
					tile_idx += 1
				end
			}

			node.repeat_index = saved_ri
			node.repeat_count = saved_rc
			subNode
		end
	end

	class Split < SubNodeGenerator
		attr_accessor :axis, :splitComponant

		def initialize( axis, splitComponant )
			self.axis = axis
			self.splitComponant = splitComponant
		end

		def apply( node, shape, position=V3._0, rotation=V3._0, scope=nil )
			splitComponant.apply( axis, node, shape )
		end
	end

	class Creational < GenerativePart
		def apply( node, position, rotation, scope )
		end
	end

	class Instantiate < Creational
		attr_accessor :shapeType, :id
		attr_accessor :shapeOptions

		def initialize( shapeType, id, shapeOptions=nil )
			self.shapeType = shapeType
			self.id = id
			self.shapeOptions = shapeOptions
		end

		def apply( node, position, rotation, scope )
			Node.new( node, id, shapeType.new( scope, shapeOptions ), position, rotation )
		end
	end

	class I < Creational
		attr_accessor :id

		def initialize( id )
			self.id = id
		end

		def apply( node, position, rotation, scope )
			shape = node.shape.clone
			shape.scope = scope
			Node.new( node, id, shape, position, rotation )
		end
	end

	class Roof < Creational
		attr_accessor :roofType, :id

		def initialize( roofType, id )
			self.roofType = roofType
			self.id = id
		end

		def apply( node, position, rotation, scope )
			Node.new( node, id, TriangularPrism.new( V3[scope.x,scope.y/4.0,scope.y]), position, V3[rotation.x-90,rotation.y,rotation.z] )
		end
	end

	class BindTexture < GenerativePart
		attr_accessor :texture

		def initialize( texture )
			self.texture = texture
		end

		def apply( shape )
			shape.texture = texture
		end
	end

	class RulesSet
		attr_accessor :rules

		def initialize
			self.rules = []
		end

		def <<(rule)
			self.rules << rule
		end

		def apply( nodes )
			subNodes = []
			nodes.each{ |node|
				if node.ruleId.is_a?(Rule)
					rule = node.ruleId
					if rule.apply?(node)
						node.subNodes.concat( rule.apply( node ) )
						subNodes.concat( node.subNodes )
					end
				else
					self.rules.each{ |rule|
						if rule.id == node.ruleId && rule.apply?(node)
							node.subNodes.concat( rule.apply( node ) )
							subNodes.concat( node.subNodes )
							break
						end
					}
				end
			}
			unless subNodes.empty?
				apply( subNodes )
			end
			nodes
		end
	end

	class Size
		attr_accessor :value

		def initialize( value )
			self.value = value
		end

		def to_s
			value
		end
	end

	class AbsoluteSize < Size
		def to_s
			value.to_s + "a"
		end
	end

	class RelativeSize < Size
		def to_s
			value.to_s + "r"
		end
	end

end
