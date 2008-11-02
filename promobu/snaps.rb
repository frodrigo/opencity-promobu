
module Snaps

	class ::Snaps::SnapPlane
		attr_accessor :snap
		attr_accessor :position
		attr_accessor :rotation

		attr_accessor :nx, :ny, :nz
		attr_accessor :d

		def a
			self.normal.x
		end

		def b
			self.normal.y
		end

		def c
			self.normal.z
		end

		attr_accessor :normal
	
		def initialize( snap, position, rotation )
			self.snap = snap
			self.position = position
			self.rotation = rotation
			r = self.rotation.rotationMatrix
			x = Vector[1,0,0,0]
			y = Vector[0,1,0,0]
			# Compute 2 free vectors of plane
			nx = r * x
			ny = r * y
			self.nx = V3[nx[0],nx[1],nx[2]]
			self.ny = V3[ny[0],ny[1],ny[2]]
			# Compute normal vector
			self.nz = self.nx.cross_product(self.ny)
			# nz.x*x + nz.y*y + nz.z*z + d = 0
			self.normal = V3[nz.x,nz.y,nz.z]
			self.d = -nz.x*position.x - nz.y*position.y - nz.z*position.z
		end

		def parallel?( vector )
			# Compute det of base vector and input vector
			vector.collinear?( self.nz )
		end

		def distance( point )
			(self.normal.x*point.x + self.normal.y*point.y + self.normal.z*point.z + self.d).abs / self.normal.r
		end
	
		def projection( point )
			d = self.normal.x*point.x + self.normal.y*point.y + self.normal.z*point.z + self.d / self.normal.r
			# Move point of d in normal dir
			point - self.normal*d
		end
	end

	class ::Snaps::SnapRegistery
		attr_accessor :snapPlanes

		include Singleton

		def initialize()
			self.snapPlanes = {}
		end

		def <<( snapPlane )
			snapGroup = snapPlane.snap.snapGroup 
			if not self.snapPlanes.key?(snapGroup) then
				self.snapPlanes[snapGroup] = []
			end
			self.snapPlanes[snapGroup] << snapPlane
		end

		def parallel( snapGroup, vector )
			if self.snapPlanes.key?(snapGroup) then
				snapPlanes[snapGroup].select{ |snapPlane|
					snapPlane.parallel?( vector )
				}
			else
				[]
			end
		end

		def nearestSnapPlane( snapGroup, position, vector )
			minPlane = nil
			minPlaneProjection = position
			min = nil
			parallel( snapGroup, vector ).each{ |snapPlane|
				m = snapPlane.distance( position )
				if m <= snapPlane.snap.snapSize and ( min == nil or m < min ) then
					minPlane = snapPlane
					minPlaneProjection = snapPlane.projection( position )
					min = m
				end
			}
			minPlaneProjection
		end
	end

	class ::Snaps::SnapPlaneRectangle < Shape::Rectangle
		attr_accessor :snap

		def initialize( snap, scope )
			self.snap = snap
			super( scope )
		end
	end

	class ::Snaps::Snap
		attr_accessor :snapGroup
		attr_accessor :snapSize

		def initialize( snapGroup, snapSize )
			self.snapGroup = snapGroup
			self.snapSize = snapSize
		end
	end

end
