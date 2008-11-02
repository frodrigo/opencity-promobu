
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
			if condition == nil then
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
				if generativePart.is_a?(ContextEdit) then
					(position, rotation, scope) = generativePart.apply( position, rotation, scope )
				elsif generativePart.is_a?(Creational) then
					returns << generativePart.apply( node, position, rotation, scope )
				elsif generativePart.is_a?(SubContext) then
					returns.concat( generate( node, generativePart.generativeParts, position, rotation, scope ) )
				elsif generativePart.is_a?(SubNodeGenerator) then
					returns.concat( generativePart.apply( node, node.shape ) )
				elsif generativePart.is_a?(BindTexture) then
					generativePart.apply( node.shape )
				end
			}
			return returns
		end
	end

	class ::Rules::GenerativePart
		def apply()
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
			if v3.is_a?(Proc) then
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

		def initialize( splitType, ids )
			self.splitType = splitType
			self.ids = ids
		end

		def apply( node, shape )
			subNode = []
			ids_local = ids.dup
			id = nil
			shape.component( splitType ).each{ |subShapeArray|
				if ids_local.length >= 1 then
					id = ids_local.shift()
				end
				subNode << Node.new( node, id, subShapeArray[2], subShapeArray[0], subShapeArray[1] )
			}
			subNode
		end
	end

	class ::Rules::Split < SubNodeGenerator
		attr_accessor :axis
		attr_accessor :parts
		attr_accessor :snapGroup

		def initialize( axis, parts, snapGroup=nil )
			self.axis = axis
			self.parts = parts
			self.snapGroup = snapGroup
		end

		def apply( node, shape )
			subNode = []
			partSizes = parts.collect{ |x| if x.is_a?(Array) then x[0] else x end }
			partIds = parts.collect{ |x| if x.is_a?(Array) then x[1] else x end }
			shape.split( node, axis, partSizes, snapGroup ).each{ |subShapeArray|
				id = partIds.shift()
				if not subShapeArray[2].is_a?(SnapPlaneRectangle) then
					subNode << Node.new( node, id, subShapeArray[2], subShapeArray[0], subShapeArray[1] )
				else
					absPosition, absRotation = node.toAbs( subShapeArray[0], subShapeArray[1] )
					SnapRegistery.instance << SnapPlane.new( subShapeArray[2].snap, absPosition, absRotation )
root = node
while root.parent != nil do root = root.parent end
root << Node.new( node, "_SnapPlaneRectangle", subShapeArray[2], absPosition, absRotation )
				end
			}
			subNode
		end
	end

	class ::Rules::Tile < SubNodeGenerator
		attr_accessor :axis
		attr_accessor :tileSize
		attr_accessor :tileId
		attr_accessor :snapPlane
		attr_accessor :snapGroup

		def initialize( axis, tileSize, tileId, snapPlane=nil, snapGroup=nil )
			self.axis = axis
			self.tileSize = tileSize
			self.tileId = tileId
			self.snapPlane = snapPlane
			self.snapGroup = snapGroup
		end

		def apply( node, shape )
			subNode = []
			shape.tile( node, axis, tileSize, snapPlane, snapGroup ).each{ |subShapeArray|
				if not subShapeArray[2].is_a?(SnapPlaneRectangle) then
					subNode << Node.new( node, tileId, subShapeArray[2], subShapeArray[0], subShapeArray[1] )
				else
					absPosition, absRotation = node.toAbs( subShapeArray[0], subShapeArray[1] )
					SnapRegistery.instance << SnapPlane.new( subShapeArray[2].snap, absPosition, absRotation )
root = node
while root.parent != nil do root = root.parent end
root << Node.new( node, "_SnapPlaneRectangle", subShapeArray[2], absPosition, absRotation )
				end
			}
			subNode
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
			if roofType == GabledRoof or true then
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
	
		def initialize()
			self.rules = []
		end

		def <<(rule)
			self.rules << rule
		end

		def apply( nodes )
			subNodes = []
			nodes.each{ |node|
				self.rules.each{ |rule|
					if rule.id == node.ruleId and rule.apply?(node) then
						node.subNodes.concat( rule.apply( node ) )
						subNodes.concat( node.subNodes )
						break
					end
				}
			}
			if subNodes != [] then
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
