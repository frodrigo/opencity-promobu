
module Rules

	class ::Rules::Rule
		attr_accessor :id
		attr_accessor :condition
		attr_accessor :generativeParts
		attr_accessor :probability

		def initialize( id, condition, generativeParts, probability=1 )
			self.id = id
			self.condition = condition
			self.generativeParts = generativeParts
			self.probability = probability
		end

		def apply?( node )
			if condition.nil?
				true
			else
				condition.call( node )
			end
		end

		def apply( node )
			generate( node, self.generativeParts, V3._0, V3._0, node.shape.scope )
		end

		def generate( node, generativeParts, position, rotation, scope )
			returns = []
			generativeParts.each { |generativePart|
				if generativePart.is_a?(ContextEdit)
					(position, rotation, scope) = generativePart.apply( position, rotation, scope )
				elsif generativePart.is_a?(Creational)
					returns << generativePart.apply( node, position, rotation, scope )
				elsif generativePart.is_a?(SubContext)
					returns.concat( generate( node, generativePart.generativeParts, position, rotation, scope ) )
				elsif generativePart.is_a?(SubNodeGenerator)
					returns.concat( generativePart.apply( node, node.shape ) )
				elsif generativePart.is_a?(BindTexture)
					generativePart.apply( node.shape )
				end
			}
			returns
		end
	end

	class ::Rules::GenerativePart
		def apply
		end
	end

	class ::Rules::SubContext < GenerativePart
		attr_accessor :generativeParts

		def initialize( generativeParts )
			self.generativeParts = generativeParts
		end
	end

	class ::Rules::ContextEdit < GenerativePart
		attr_accessor :v3

		def initialize( v3 )
			self.v3 = v3
		end

		def apply( position, rotation, scope )
			[ position, rotation, scope ]
		end
	end

	class ::Rules::Translation < ContextEdit
		def apply( position, rotation, scope )
			[ position+v3, rotation, scope ]
		end
	end

	class ::Rules::Rotation < ContextEdit
		def apply( position, rotation, scope )
			[ position, rotation+v3, scope ]
		end
	end

	class ::Rules::Scope < ContextEdit
		def apply( position, rotation, scope )
			if v3.is_a?(Proc)
				[ position, rotation, v3.call(scope) ]
			else
				[ position, rotation, scope+v3 ]
			end
		end
	end

	class ::Rules::SubNodeGenerator < GenerativePart
		def apply( node, shape )
			[]
		end
	end

	class ::Rules::Component < SubNodeGenerator
		attr_accessor :splitType
		attr_accessor :ids
		attr_accessor :condition

		def initialize( splitType, ids, condition=nil )
			self.splitType = splitType
			self.ids = ids
			self.condition = condition
		end

		def apply( node, shape )
			return [] if condition && !condition.call( node )
			components = shape.component( splitType )
			return [] if components.nil?
			subNode = []
			ids_local = ids.dup
			id = nil
			components.each{ |subShapeArray|
				if ids_local.length >= 1
					id = ids_local.shift
				end
				subNode << Node.new( node, id, subShapeArray[2], subShapeArray[0], subShapeArray[1] )
			}
			subNode
		end
	end

	class ::Rules::SplitComponant
	end

	class ::Rules::SplitElement < SplitComponant
		attr_accessor :parts
		attr_accessor :snapGroup

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
					absPosition, absRotation = node.toAbs( subShapeArray[0], subShapeArray[1] )
					SnapRegistery.instance << SnapPlane.new( subShapeArray[2].snap, absPosition, absRotation )
root = node
root = root.parent until root.parent.nil?
root << Node.new( node, "_SnapPlaneRectangle", subShapeArray[2], absPosition, absRotation )
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

	class ::Rules::SplitRepeat < SplitComponant
		attr_accessor :tileSize
		attr_accessor :splitComponant
		attr_accessor :snapPlane
		attr_accessor :snapGroup

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
					absPosition, absRotation = node.toAbs( subShapeArray[0], subShapeArray[1] )
					SnapRegistery.instance << SnapPlane.new( subShapeArray[2].snap, absPosition, absRotation )
root = node
root = root.parent until root.parent.nil?
root << Node.new( node, "_SnapPlaneRectangle", subShapeArray[2], absPosition, absRotation )
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

	class ::Rules::Split < SubNodeGenerator
		attr_accessor :axis
		attr_accessor :splitComponant

		def initialize( axis, splitComponant )
			self.axis = axis
			self.splitComponant = splitComponant
		end

		def apply( node, shape )
			splitComponant.apply( axis, node, shape )
		end
	end

	class ::Rules::Creational < GenerativePart
		def apply( node, position, rotation, scope )
		end
	end

	class ::Rules::Instantiate < Creational
		attr_accessor :shapeType
		attr_accessor :id

		def initialize( shapeType, id )
			self.shapeType = shapeType
			self.id = id
		end

		def apply( node, position, rotation, scope )
			Node.new( node, id, shapeType.new( scope ), position, rotation )
		end
	end

	class ::Rules::I < Creational
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

	class ::Rules::Roof < Creational
		attr_accessor :roofType
		attr_accessor :id

		def initialize( roofType, id )
			self.roofType = roofType
			self.id = id
		end

		def apply( node, position, rotation, scope )
			if roofType == GabledRoof || true
				Node.new( node, id, TriangularPrism.new( V3[scope.x,scope.y/4.0,scope.y]), position, V3[rotation.x-90,rotation.y,rotation.z] )
			end
		end
	end

	class ::Rules::BindTexture < GenerativePart
		attr_accessor :texture

		def initialize( texture )
			self.texture = texture
		end

		def apply( shape )
			shape.texture = texture
		end
	end

	class ::Rules::RulesSet
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
				self.rules.each{ |rule|
					if rule.id == node.ruleId && rule.apply?(node)
						node.subNodes.concat( rule.apply( node ) )
						subNodes.concat( node.subNodes )
						break
					end
				}
			}
			unless subNodes.empty?
				apply( subNodes )
			end
			nodes
		end
	end

	class ::Rules::Size
		attr_accessor :value

		def initialize( value )
			self.value = value
		end

		def to_s
			value
		end
	end

	class ::Rules::AbsoluteSize < Size
		def to_s
			value.to_s + "a"
		end
	end

	class ::Rules::RelativeSize < Size
		def to_s
			value.to_s + "r"
		end
	end

end
