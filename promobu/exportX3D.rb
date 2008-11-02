
module ExportX3D
	def self.export( root, fileName )
		x3d = REXML::Document.new()
		x3d.add(REXML::XMLDecl.new(REXML::XMLDecl::DEFAULT_VERSION,REXML::XMLDecl::DEFAULT_ENCODING))
		x3dRoot = x3d.add_element("X3D", {"profile"=>"Immersive", "version"=>"2.0"})
		x3dScene = x3dRoot.add_element("Scene")
		root.exportX3D(x3dScene)
		x3d.write(File.new(fileName, "w"),2)
	end
end

module ProcedureBuildingGenerator
	class Node
		def euler2AxisAngle( rotation )
			c1 = Math.degCos(rotation.y/2.0)
			c2 = Math.degCos(rotation.z/2.0)
			c3 = Math.degCos(rotation.x/2.0)
			s1 = Math.degSin(rotation.y/2.0)
			s2 = Math.degSin(rotation.z/2.0)
			s3 = Math.degSin(rotation.x/2.0)
			angle = 2 * Math.acos(c1*c2*c3 - s1*s2*s3)
			x = s1*s2*c3 + c1*c2*s3
			y = s1*c2*c3 + c1*s2*s3
			z = c1*s2*c3 - s1*c2*s3
			[V3[x,y,z],angle]
		end

		def exportX3D( node )
			# #{ruleId}
			euler = euler2AxisAngle( rotation )
			trans = {}
			if position.x != 0 or position.y != 0 or position.z !=0  then
				trans["translation"] = "#{position.x} #{position.y} #{position.z}"
			end
			if euler != [V3._0,0] then
				trans["rotation"] = "#{euler[0].x} #{euler[0].y} #{euler[0].z} #{euler[1]}"
			end
			if trans != {} then
				transform = node.add_element("Transform", trans)
			else
				transform = node
			end
			if subNodes == [] then
				transform.add_text( "<!--#{ruleId}-->" )
				shape.exportX3D( transform )
			else
				subNodes.each{ |subNode|
					subNode.exportX3D( transform )
				}
			end
		end
	end
end


module Shapes
	class ::Shapes::Shape
		def exportX3D( node )
			if self.texture then
				appearance = node.add_element( "Appearance" )
				appearance.add_element( "ImageTexture", {"url"=>"#{self.texture.textureFile}"} )
			end
		end
	end

	class ::Shapes::Rectangle < Shape2D
		def exportX3D( node )
			shape = node.add_element( "Shape" )
			super( shape )
			shape = shape.add_element( "IndexedFaceSet", {"coordIndex"=>"3 2 1 0 -1"} )
			shape.add_element( "Coordinate", {"point"=>"0 0 0  #{scope.x} 0 0  #{scope.x} #{scope.y} 0  0 #{scope.y} 0"} )
			shape.add_element( "TextureCoordinate", {"point"=>"0 0  1 0  1 1  0 1"} )
		end
	end

	class ::Shapes::IsoscelesTriangle < Shape2D
		def exportX3D( node )
			shape = node.add_element( "Shape" )
			super( shape )
			shape = shape.add_element( "IndexedFaceSet", {"coordIndex"=>"2 1 0 -1"} )
			shape.add_element( "Coordinate", {"point"=>"0 0 0  #{scope.x} 0 0  #{scope.x/2.0} #{scope.y} 0"} )
			shape.add_element( "TextureCoordinate", {"point"=>"0 0  1 0  0.5 1"} )
		end
	end

	class ::Shapes::Box < Shape3D
		def exportX3D( node )
			node = node.add_element("Transform", {"translation"=>"#{scope.x/2.0} #{scope.y/2.0} #{scope.z/2.0}"} )
			shape = node.add_element( "Shape" )
			super( shape )
			shape.add_element( "Box", {"size"=>"#{scope.x} #{scope.y} #{scope.z}"} )
		end
	end
end
