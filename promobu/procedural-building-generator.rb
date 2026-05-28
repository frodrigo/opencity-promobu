require 'rexml/document'
require 'singleton'
require 'matrix'

module Math
	def Math.degCos( a )
		case a%360
			when 0 then 1
			when 90 then 0
			when 180 then -1
			when 270 then 0
			else Math.cos(a*Math::PI/180)
		end
	end

	def Math.degSin( a )
		case a%360
			when 0 then 0
			when 90 then 1
			when 180 then 0
			when 270 then -1
			else Math.sin(a*Math::PI/180)
		end
	end
end

class Vector
	def x; self[0]; end
	def y; self[1]; end
	def z; self[2]; end

	def to_s
		"#{x},#{y},#{z}"
	end

	def cross_product( v )
		V3[y*v.z-z*v.y, z*v.x-x*v.z, x*v.y-y*v.x]
	end

	def collinear?( v )
		cos = ( self.x*v.x + self.y*v.y + self.z*v.z ) / Float( self.r * v.r )
		(cos-1).abs < 1e-15 || (cos+1).abs < 1e-15
	end

	def eql?( v )
		self == v
	end

	def rotationMatrix
		rx = Matrix[
			[1,0,0,0],
			[0,Math::degCos(self.x),Math::degSin(self.x),0],
			[0,-Math::degSin(self.x),Math::degCos(self.x),0],
			[0,0,0,1]]
		ry = Matrix[
			[Math::degCos(self.y),0,-Math::degSin(self.y),0],
			[0,1,0,0],
			[Math::degSin(self.y),0,Math::degCos(self.y),0],
			[0,0,0,1]]
		rz = Matrix[
			[Math::degCos(self.z),Math::degSin(self.z),0,0],
			[-Math::degSin(self.z),Math::degCos(self.z),0,0],
			[0,0,1,0],
			[0,0,0,1]]
		rx * ry * rz
	end

	def reverseRotationMatrix
		rx = Matrix[
			[1,0,0,0],
			[0,Math::degCos(-self.x),Math::degSin(-self.x),0],
			[0,-Math::degSin(-self.x),Math::degCos(-self.x),0],
			[0,0,0,1]]
		ry = Matrix[
			[Math::degCos(-self.y),0,-Math::degSin(-self.y),0],
			[0,1,0,0],
			[Math::degSin(-self.y),0,Math::degCos(-self.y),0],
			[0,0,0,1]]
		rz = Matrix[
			[Math::degCos(-self.z),Math::degSin(-self.z),0,0],
			[-Math::degSin(-self.z),Math::degCos(-self.z),0,0],
			[0,0,1,0],
			[0,0,0,1]]
		rz * ry * rx
	end

	def translationMatrix
		Matrix[
			[1,0,0,self.x],
			[0,1,0,self.y],
			[0,0,1,self.z],
			[0,0,0,1]]
	end

	def reverseTranslationMatrix
		Matrix[
			[1,0,0,-self.x],
			[0,1,0,-self.y],
			[0,0,1,-self.z],
			[0,0,0,1]]
	end
end

class V3 < Vector
	@@_0 = V3[0,0,0]

	def V3._0
		@@_0
	end
end

class V2 < Vector
	def x; self[0]; end
	def y; self[1]; end
	def z; 0; end

	def to_s
		"#{x},#{y}"
	end
end

module ProcedureBuildingGenerator

	class Node
		attr_accessor :parent
		attr_accessor :ruleId
		attr_accessor :shape
		attr_accessor :position
		attr_accessor :rotation
		attr_accessor :subNodes
		attr_accessor :repeat_index   # index of this tile within a SplitRepeat (nil if not in a repeat)
		attr_accessor :repeat_count   # total tile count of the enclosing SplitRepeat (nil if not in a repeat)

		def initialize( parent, ruleId, shape, position, rotation )
			self.parent = parent
			self.ruleId = ruleId
			self.shape = shape
			self.position = position
			self.rotation = rotation
			self.subNodes = []
		end

		def <<( subNode )
			self.subNodes << subNode
		end

		def to_s
			"#{ruleId}:#{shape}@(#{position})[#{subNodes}]"
		end

		def Node.baseChange( basePosition, baseRotation, position, rotation )
			r = baseRotation.rotationMatrix
			t = basePosition.reverseTranslationMatrix
			position = Vector[position[0], position[1], position[2], 1]
			nPosition = r * t * position
			nPosition = V3[nPosition[0], nPosition[1], nPosition[2]]
			nRotation = baseRotation + rotation
			[ nPosition, nRotation ]
		end

		def Node.baseUnChange( basePosition, baseRotation, position, rotation )
			r = baseRotation.reverseRotationMatrix
			t = basePosition.translationMatrix
			position = Vector[position[0], position[1], position[2], 1]
			nPosition = t * r * position
			nPosition = V3[nPosition[0], nPosition[1], nPosition[2]]
			nRotation = baseRotation + rotation
			[ nPosition, nRotation ]
		end

		def toAbs( position, rotation )
			if self.parent.nil?
				[ position, rotation ]
			else
				(position, rotation) = Node.baseUnChange( self.position, self.rotation, position, rotation )
				self.parent.toAbs( position, rotation )
			end
		end

		def toRelative( position, rotation )
			if self.parent.nil?
				[ position, rotation ]
			else
				(position, rotation) = self.parent.toRelative( position, rotation )
				Node.baseChange( self.position, self.rotation, position, rotation )
			end
		end

		def abs!
			unless self.parent.nil?
				(self.position, self.rotation) = Node.baseUnChange( self.parent.position, self.parent.rotation, self.position, self.rotation )
			end
			self.subNodes.collect!{ |subNode|
				subNode.abs!
			}
			unless self.subNodes.empty?
				(self.position, self.rotation) = [V3._0, V3._0]
			end
			self
		end

		def queryAbsRotation?( queryRotation )
			r = toAbs( V3._0, V3._0 )[1]
			( r.x%360 - queryRotation.x ).abs < 1e-15 && ( r.y%360 - queryRotation.y ).abs < 1e-15 && ( r.z%360 - queryRotation.z ).abs < 1e-15
		end

		def dir
			r = rotation.rotationMatrix
			zaxis = Vector[ZAxis.vector[0], ZAxis.vector[1], ZAxis.vector[2], 1]
			dir = r * zaxis
			V3[dir.x, dir.y, dir.z]
		end

		def getAllLeafNode
			if subNodes.empty?
				[self]
			else
				self.subNodes.map { |subNode|
					subNode.getAllLeafNode
				}.flatten!
			end
		end

	end

	class Axis
		@@vector = V3[0,0,0]
		def Axis.vector()
			@@vector
		end
		def Axis.component( v ) 0 end
	end

	class XAxis < Axis
		@@vector_ = V3[1,0,0]
		def XAxis.vector()
			@@vector_
		end
		def XAxis.component( v ) v.x end
	end

	class YAxis < Axis
		@@vector_ = V3[0,1,0]
		def YAxis.vector()
			@@vector_
		end
		def YAxis.component( v ) v.y end
	end

	class ZAxis < Axis
		@@vector_ = V3[0,0,1]
		def ZAxis.vector()
			@@vector_
		end
		def ZAxis.component( v ) v.z end
	end

	class Texture
		attr_accessor :textureFile
		attr_accessor :double_side
		attr_accessor :sprite_frame

		def initialize( textureFile )
			self.textureFile = textureFile
			self.double_side = false
			self.sprite_frame = nil
		end

		def eql?( other )
			self.class == other.class &&
				self.textureFile == other.textureFile &&
				self.double_side == other.double_side &&
				self.sprite_frame == other.sprite_frame
		end

		# Map [u,v] in local [0..1] space to atlas space when sprite metadata exists.
		# If repeat_x is enabled, the U coordinate is tiled according to the face
		# width relative to the sprite aspect ratio while V remains fit to height.
		def map_uv( u, v, shape_w=nil, shape_h=nil )
			return [u, v] if self.sprite_frame.nil?

			ax = self.sprite_frame[:x].to_f
			ay = self.sprite_frame[:y].to_f
			aw = self.sprite_frame[:w].to_f
			ah = self.sprite_frame[:h].to_f
			atlas_w = self.sprite_frame[:atlas_w].to_f
			atlas_h = self.sprite_frame[:atlas_h].to_f

			u0 = ax / atlas_w
			u1 = (ax + aw) / atlas_w
			v0 = ay / atlas_h
			v1 = (ay + ah) / atlas_h

			if self.sprite_frame[:repeat_x] && shape_w && shape_h && shape_h.to_f > 0.0
				tile_w = shape_h.to_f * (aw / ah)
				if tile_w > 0.0
					repeats = shape_w.to_f / tile_w
					u = (u * repeats) % 1.0
				end
			end

			[ u0 + (u1 - u0) * u, v0 + (v1 - v0) * v ]
		end
	end

	class AdaptedTexture < Texture
		def initialize( textureFile )
			super( textureFile )
		end
	end

	class TiledTexture < Texture
		attr_accessor :w
		attr_accessor :h

		def initialize( textureFile, w, h )
			super( textureFile )
			self.w = w
			self.h = h
		end

		def eql?( other )
			if other.is_a?(TiledTexture)
				super(other) && self.w == other.w && self.h == other.h
			else
				false
			end
		end
	end

end
