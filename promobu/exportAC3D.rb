
module ExportAC3D
	def self.export( root, fileName )
		ac3d = File.new(fileName, "w")
		ac3d.write("AC3Db\n")
		root.exportAC3D(ac3d)
		ac3d.close
		
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

		def exportAC3D( ac3d )
			ac3d.write("OBJECT\n")
			if position.x != 0 or position.y != 0 or position.z !=0  then
				ac3d.write("loc #{position.x} #{position.y} #{position.z}\n")
			end
			if rotation.x != 0 or rotation.y != 0 or rotation.z !=0  then
				rotationMatrix = rotation.rotationMatrix
				ac3d.write("rot #{rotationMatrix[0,0]} #{rotationMatrix[0,1]} #{rotationMatrix[0,2]} #{rotationMatrix[1,0]} #{rotationMatrix[1,1]} #{rotationMatrix[1,2]} #{rotationMatrix[2,0]} #{rotationMatrix[2,1]} #{rotationMatrix[2,2]}\n")
			end
			ac3d.write("name \"#{ruleId}\"\n")
			if subNodes == [] then
				ac3d.write("kids 1\n")
				ac3d.write("OBJECT\n")
				shape.exportAC3D( ac3d )
				ac3d.write("kids 0\n")
			else
				ac3d.write("kids #{subNodes.length}\n")
				subNodes.each{ |subNode|
					subNode.exportAC3D( ac3d )
				}
			end
		end
	end
end


module Shapes
	class ::Shapes::Shape
		def exportAC3D( ac3d )
			if self.texture then
				ac3d.write("texture \"#{self.texture.textureFile}\"\n")
			end
		end
	end

	class ::Shapes::Rectangle < Shape2D
		def exportAC3D( ac3d )
			ac3d.write("name \"Rectangle\"\n")
			super( ac3d )
			ac3d.write("numvert #{4}\n")
			ac3d.write("0 0 0\n")
			ac3d.write("#{scope.x} 0 0\n")
			ac3d.write("#{scope.x} #{scope.y} 0\n")
			ac3d.write("0 #{scope.y} 0\n")
			ac3d.write("numsurf 1\n")
			ac3d.write("SURF 0x10\n")
			ac3d.write("refs 4\n")
			ac3d.write("3 0 1\n")
			ac3d.write("2 1 1\n")
			ac3d.write("1 1 0\n")
			ac3d.write("0 0 0\n")
		end
	end

	class ::Shapes::IsoscelesTriangle < Shape2D
		def exportAC3D( ac3d )
			ac3d.write("name \"IsoscelesTriangle\"\n")
			super( ac3d )
			ac3d.write("numvert #{3}\n")
			ac3d.write("0 0 0\n")
			ac3d.write("#{scope.x} 0 0\n")
			ac3d.write("#{scope.x/2.0} #{scope.y} 0\n")
			ac3d.write("numsurf 1\n")
			ac3d.write("SURF 0x10\n")
			ac3d.write("refs 3\n")
			ac3d.write("2 0.5 1\n")
			ac3d.write("1 1 0\n")
			ac3d.write("0 0 0\n")
		end
	end

	class ::Shapes::Box < Shape3D
		def exportAC3D( node )
			#node = node.add_element("Transform", {"translation"=>"#{scope.x/2.0} #{scope.y/2.0} #{scope.z/2.0}"} )
			#shape = node.add_element( "Shape" )
			#super( shape )
			#shape.add_element( "Box", {"size"=>"#{scope.x} #{scope.y} #{scope.z}"} )
		end
	end
end
