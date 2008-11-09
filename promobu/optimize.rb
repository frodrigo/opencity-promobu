
require 'set.rb'

module Optimize

	class ::Optimize::BoundingBox
		attr_accessor :x1
		attr_accessor :y1
		attr_accessor :x2
		attr_accessor :y2
		
		def initialize( x1, y1, x2, y2 )
			self.x1 = x1
			self.y1 = y1
			self.x2 = x2
			self.y2 = y2
		end
		
		def intersect?( other )
			not( 1e-12 < self.x1 - other.x2 or other.x1 - self.x2 > 1e-12 or 1e-12 < self.y1 - other.y2 or 1e-12 > self.y2 - other.y1 )
		end
		
		def +( other )
			copy = self.clone
			copy.x1 = self.x1 < other.x1 ? self.x1 : other.x1
			copy.y1 = self.y1 < other.y1 ? self.y1 : other.y1
			copy.x2 = self.x2 > other.x2 ? self.x2 : other.x2
			copy.y2 = self.y2 > other.y2 ? self.y2 : other.y2
			copy
		end
		
		def ==( other )
			self.x1 == other.x1 and self.y1 == other.y1 and self.x2 == other.x2 and self.y2 == other.y2
		end
		
		def to_s
			"\n(#{self.x1},#{self.y1}-#{self.x2},#{self.y2})"
		end
	end

	class ::Optimize::ConcomitantRegistery
		attr_accessor :set

		def initialize( node, relativePosition )
			nodeBoundingBox = BoundingBox.new( relativePosition.x, relativePosition.y, relativePosition.x + node.shape.scope.x, relativePosition.y + node.shape.scope.y )
			self.set = {nodeBoundingBox => [node]}
		end

		def add( node, relativePosition )
			mergeBoundingBox = BoundingBox.new( relativePosition.x, relativePosition.y, relativePosition.x + node.shape.scope.x, relativePosition.y + node.shape.scope.y )
			mergeNode = [node]
			merge = true
			while( merge )
				merge = false
				newSet = self.set.clone

				self.set.each { |boundingBox, nodeList|
					if mergeBoundingBox.intersect?( boundingBox ) then
						origMergeBoundingBox = mergeBoundingBox
						mergeBoundingBox += boundingBox
						mergeNode.concat( nodeList )
						newSet.delete( boundingBox )
						merge = (origMergeBoundingBox != mergeBoundingBox)
					end
				}
				self.set = newSet
			end
			self.set[mergeBoundingBox] = mergeNode
		end

		def mergable
			set.values
		end
	end	

	class ::Optimize::CoplanarRegistery
		attr_accessor :dir
		attr_accessor :set
		attr_accessor :position
		attr_accessor :rotation

		def initialize( dir, node )
			self.dir = dir
			self.set = {}
			self.position = node.position
			self.rotation = node.rotation

			self << node
		end

		def <<( node )
			relativePosition = Node.baseChange( self.position, self.rotation, node.position, node.rotation )[0]

			d = -( dir.x*node.position.x + dir.y*node.position.y + dir.z*node.position.z )
			d = (d*1e12).round*1e-12
			if not set.has_key?(d) then
				set[d] = ConcomitantRegistery.new( node, relativePosition )
			else
				set[d].add( node, relativePosition )
			end
		end

		def mergable
			set.values.collect{ |plan|
				plan.mergable
			}
		end
	end

	class ::Optimize::CollinearRegistery
		include Singleton

		attr_accessor :set

		def initialize()
			self.set = {}
		end

		def addNodes( nodes )
			nodes.each{ |node|
				addNode( node )
			}
		end
	
		def addNode( node )
			dir = node.dir
			if not self.set.has_key?(dir) then
				self.set[dir] = CoplanarRegistery.new( dir, node )
			else
				self.set[dir] << node
			end
		end

		def mergable
			set.values.collect{ |dir|
				dir.mergable
			}
		end
	end

	class ::Optimize::AggregatedTexture
		@@count = 0

		attr_accessor :fileName

		attr_accessor :tiles
		attr_accessor :w
		attr_accessor :h

		attr_accessor :sameMaster

		def initialize( w, h )
			self.tiles = {}
			self.w = w
			self.h = h
			self.sameMaster = nil
			@@count = @@count + 1
			self.fileName = "texture-#{@@count}"
		end

		def addZone( node, position, rotation )
			position = V3[(position.x*1e12).round*1e-12, (position.y*1e12).round*1e-12, 0]
			rotation = V3[rotation.x%360, rotation.y%360, rotation.z%360]
			self.tiles[[position,rotation]] = node
		end

		def file
			if sameMaster == nil then
				self.fileName
			else
				sameMaster.file
			end
		end

		def hash
			tiles.keys.collect{ |pr| pr[0] }.sort{ |a,b| a.x==b.x ? a.y==b.y ? a.z==b.z ? 0 : a.z<=>b.z : a.y<=>b.y : a.x<=>b.x }.hash
		end

		def eql?( other )
			if self.sameMaster == nil then
				if self.tiles.size == other.tiles.size then
					tiles.each_key { |key|
						if other.tiles.has_key?( key ) then
							if self.tiles[key].shape.class != other.tiles[key].shape.class or not self.tiles[key].shape.texture.eql?( other.tiles[key].shape.texture ) then
								return false
							end
							if self.tiles[key].shape.texture.is_a?(TiledTexture) and ( (self.tiles[key].shape.scope.x - other.tiles[key].shape.scope.x).abs > 1e-12 or (self.tiles[key].shape.scope.y - other.tiles[key].shape.scope.y).abs > 1e-12 ) then
								return false
							end
						else
							return false
						end
					}
				else
					return false
				end
				self.sameMaster = other.sameMaster == nil ? other : other.sameMaster
				true
			elsif self.sameMaster != other then
				false
			else # sameMaster == other
				true
			end
		end
	end

	class AggregatedAdaptedTexture < AdaptedTexture
		attr_accessor :aggregatedTexture
	
		def initialize( aggregatedTexture )
			super( nil )
			self.aggregatedTexture = aggregatedTexture
		end
		
		def textureFile
			aggregatedTexture.file + ".png"
		end
	end

	def self.optimize( root )
		root.abs!
		leafNodes = root.getAllLeafNode

		laef2DShapeNodes = leafNodes.select{ |node|
			node.shape.is_a?(Shape2D)
		}

		
		CollinearRegistery.instance.addNodes( laef2DShapeNodes )

		newRoot = Node.new( nil, "root", Box.new(V3[8,5,3]), V3._0, V3._0 )

		textures = CollinearRegistery.instance.set.collect{ |k,v|
			v.set.collect{ |kk,vv|
				vv.set.collect{ |kkk,vvv|
					position = vvv[0].position
					rotation = vvv[0].rotation
					minX = maxX = minY = maxY = 0
					texturePlan = vvv.collect{ |node|
						x0y0 = V3[0,0,0]
						x1y0 = V3[node.shape.scope.x,0,0]
						x1y1 = V3[node.shape.scope.x,node.shape.scope.y,0]
						x0y1 = V3[0,node.shape.scope.y,0]
						enum = [x0y0, x1y0, x1y1, x0y1]
	
						x0y0 = Node.baseUnChange( node.position, node.rotation, x0y0, V3._0 )[0]
						x1y0 = Node.baseUnChange( node.position, node.rotation, x1y0, V3._0 )[0]
						x1y1 = Node.baseUnChange( node.position, node.rotation, x1y1, V3._0 )[0]
						x0y1 = Node.baseUnChange( node.position, node.rotation, x0y1, V3._0 )[0]
	
						x0y0 = Node.baseChange( position, rotation, x0y0, V3._0 )[0]
						x1y0 = Node.baseChange( position, rotation, x1y0, V3._0 )[0]
						x1y1 = Node.baseChange( position, rotation, x1y1, V3._0 )[0]
						x0y1 = Node.baseChange( position, rotation, x0y1, V3._0 )[0]
	
						enum = [x0y0, x1y0, x1y1, x0y1]
						min_x = enum.min { |a,b| a.x <=> b.x }.x
						min_y = enum.min { |a,b| a.y <=> b.y }.y
						max_x = enum.max { |a,b| a.x <=> b.x }.x
						max_y = enum.max { |a,b| a.y <=> b.y }.y
	
						minX = minX < min_x ? minX : min_x;
						minY = minY < min_y ? minY : min_y;
						maxX = maxX > max_x ? maxX : max_x;
						maxY = maxY > max_y ? maxY : max_y;
						relativePosition = Node.baseChange( position, rotation, node.position, node.rotation )
						[node, relativePosition]
					}
					size = V3[maxX-minX, maxY-minY, 0]
					shift = V3[minX, minY, 0]
					aggregatedTexture = AggregatedTexture.new(size.x, size.y)
					texturePlan.each{ |nodeRelPos|
						nodeRelPos[1][0] -= shift
						aggregatedTexture.addZone( nodeRelPos[0], nodeRelPos[1][0], nodeRelPos[1][1] )
					}
					shape = Rectangle.new( size )
					shape.texture = AggregatedAdaptedTexture.new(aggregatedTexture)
					newPosition = Node.baseUnChange( position, rotation, shift, V3._0 )[0]
					newRoot << Node.new( newRoot, "aggregatedTexture", shape, newPosition, rotation )
					aggregatedTexture
				}
			}
		}.flatten

		textures.uniq!

		textures.each { |texture|
			texture.exportSVG
		}

		newRoot
	end

end
