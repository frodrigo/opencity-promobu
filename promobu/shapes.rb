
module Shapes

	class ::Shapes::Shape
		attr_accessor :scope
		attr_accessor :texture

		def initialize( scope )
			self.scope = scope
		end

		def component( splitType )
		end

		def absolutPartSizes( length, partSizes )
			# length = 2 + 1r + 1 + 2r + 2 => compute r value
			sumAbsolute = sumRelative = 0
			partSizes.each{ |size|
				if size.is_a?(AbsoluteSize)
					sumAbsolute += size.value
				elsif size.is_a?(RelativeSize)
					sumRelative += size.value
				end
			}
			# compute 1r value
			r = (length - sumAbsolute) / Float(sumRelative)
			returns = []
			partSizes.each{ |size|
				if size.is_a?(AbsoluteSize)
					returns << size.value
				elsif size.is_a?(RelativeSize)
					returns << size.value * r
				else
					returns << size
				end
			}
			returns
		end

		def snap( node, axis, snapGroup, partSize, length )
			sum = newSum = 0
			last = 0
			newPart = partSize.collect{ |part|
				unless part.is_a?(Snap)
					sum += part
					snapedPosition = SnapRegistery.instance.nearestSnapPlane(
						snapGroup,
						#pos
						node.toAbs( axis.vector * sum, V3._0 )[0],
						# axis.vector
						node.toAbs( axis.vector, V3._0 )[0] - node.toAbs( V3._0, V3._0 )[0] )
					newSum = node.toRelative( snapedPosition, V3._0 )[0].r
					part = newSum-last
					last = newSum
					part
				else
					part
				end
			}
			if newSum != length
				newPart << length-newSum
			end
			newPart
		end

		def tile( node, axis, tileSize, snapPlane=nil, snapGroup=false )
			length = Float(axis.component(scope))
			nbTiles = ( length/Float(tileSize) ).floor
			# Adjust tileSize to fill completly
			tileSize = length/Float(nbTiles)

			if nbTiles <= 0
				return []
			end

			if snapPlane
				if nbTiles >= 2
					partSize = [tileSize,snapPlane] * (nbTiles-1) + [tileSize]
				else
					partSize = [tileSize]
				end
			else
				partSize = [tileSize] * nbTiles
			end
			if snapGroup
				subDivise( axis, snap(node, axis, snapGroup, partSize, length) )
			else
				subDivise( axis, partSize )
			end
		end

		def split( node, axis, partSizes, snapGroup=nil )
			length = axis.component(scope)
			absPartSizes = absolutPartSizes( length, partSizes )
			if snapGroup
				subDivise( axis, snap(node, axis, snapGroup, absPartSizes, length) )
			else
				subDivise( axis, absPartSizes )
			end
		end

		def to_s
			self.class.to_s + "(#{scope})"
		end
	end

	class ::Shapes::Shape0D < Shape
	end

	class ::Shapes::Shape2D < Shape
	end

	class ::Shapes::Shape3D < Shape
	end

	class ::Shapes::Empty < Shape0D
	end

	class ::Shapes::Rectangle < Shape2D
		def subDivise( axis, absPartSizes )
			returns = []
			if axis == XAxis
				sumAbsPartSize = 0
				absPartSizes.each{ |absPartSize|
					unless absPartSize.is_a?(Snap)
						returns << [ V3[sumAbsPartSize,0,0], V3._0, Rectangle.new(V2[absPartSize,scope.y]) ]
						sumAbsPartSize += absPartSize
					else
						returns << [ V3[sumAbsPartSize,0,0], V3[0,-90,0], SnapPlaneRectangle.new(absPartSize, V2[scope.y*1.1,scope.y*1.1]) ]
					end
				}
			elsif axis == YAxis
				sumAbsPartSize = 0
				absPartSizes.each{ |absPartSize|
					unless absPartSize.is_a?(Snap)
						returns << [ V3[0,sumAbsPartSize,0], V3._0, Rectangle.new(V2[scope.x,absPartSize]) ]
						sumAbsPartSize += absPartSize
					else
						returns << [ V3[0,sumAbsPartSize,0], V3[-90,0,0], SnapPlaneRectangle.new(absPartSize, V2[scope.x*1.1,scope.x*1.1]) ]
					end
				}
			end
			returns
		end
	end

	class ::Shapes::IsoscelesTriangle < Shape2D
	end

	class ::Shapes::Box < Shape3D
		def componentBottom; [ V3[0,0,scope.z], V3[-90,0,0], Rectangle.new(V2[scope.x,scope.z]) ]; end

		def componentTop; [ V3[0,scope.y,0], V3[90,0,0], Rectangle.new(V2[scope.x,scope.z]) ]; end

		def componentFront; [ V3._0, V3._0, Rectangle.new(V2[scope.x,scope.y]) ]; end

		def componentBack; [ V3[scope.x,0,scope.z], V3[0,180,0], Rectangle.new(V2[scope.x,scope.y]) ]; end

		def componentLeft; [ V3[0,0,scope.z], V3[0,90,0], Rectangle.new(V2[scope.z,scope.y]) ]; end

		def componentRight; [ V3[scope.x,0,0], V3[0,-90,0], Rectangle.new(V2[scope.z,scope.y]) ]; end

		# Reverse (inward-facing) variants — same plane, flipped normal
		def componentReverseFront;  [ V3[scope.x,0,0],         V3[0,180,0], Rectangle.new(V2[scope.x,scope.y]) ]; end
		def componentReverseBack;   [ V3[0,0,scope.z],         V3._0,       Rectangle.new(V2[scope.x,scope.y]) ]; end
		def componentReverseLeft;   [ V3[0,0,0],               V3[0,-90,0], Rectangle.new(V2[scope.z,scope.y]) ]; end
		def componentReverseRight;  [ V3[scope.x,0,scope.z],   V3[0,90,0],  Rectangle.new(V2[scope.z,scope.y]) ]; end
		def componentReverseTop;    [ V3[0,scope.y,scope.z],   V3[-90,0,0], Rectangle.new(V2[scope.x,scope.z]) ]; end
		def componentReverseBottom; [ V3[0,0,0],               V3[90,0,0],  Rectangle.new(V2[scope.x,scope.z]) ]; end

		def component( splitType )
			if splitType == SideFaces
				[ componentFront, componentBack, componentLeft, componentRight ]
			elsif splitType == RightFace
				[ componentRight ]
			elsif splitType == LeftFace
				[ componentLeft ]
			elsif splitType == TopFace
				[ componentTop ]
			elsif splitType == BottomFace
				[ componentBottom ]
			elsif splitType == FrontFace
				[ componentFront ]
			elsif splitType == BackFace
				[ componentBack ]
			elsif splitType == ReverseFrontFace
				[ componentReverseFront ]
			elsif splitType == ReverseBackFace
				[ componentReverseBack ]
			elsif splitType == ReverseLeftFace
				[ componentReverseLeft ]
			elsif splitType == ReverseRightFace
				[ componentReverseRight ]
			elsif splitType == ReverseTopFace
				[ componentReverseTop ]
			elsif splitType == ReverseBottomFace
				[ componentReverseBottom ]
			elsif splitType == ReverseSideFaces
				[ componentReverseFront, componentReverseBack, componentReverseLeft, componentReverseRight ]
			elsif splitType == ReverseAllFaces
				[ componentReverseBottom, componentReverseTop, componentReverseFront, componentReverseBack, componentReverseLeft, componentReverseRight ]
			else
				[ componentBottom, componentTop, componentFront, componentBack, componentLeft, componentRight ]
			end
		end

		def subDivise( axis, absPartSizes )
			returns = []
			if axis == XAxis
				sumAbsPartSize = 0
				absPartSizes.each{ |absPartSize|
					unless absPartSize.is_a?(Snap)
						returns << [ V3[sumAbsPartSize,0,0], V3._0, Box.new(V3[absPartSize,scope.y,scope.z]) ]
						sumAbsPartSize += absPartSize
					else
						returns << [ V3[sumAbsPartSize,0,0], V3[0,-90,0], SnapPlaneRectangle.new(absPartSize, V2[scope.z*1.1,scope.y*1.1]) ]
					end
				}
			elsif axis == YAxis
				sumAbsPartSize = 0
				absPartSizes.each{ |absPartSize|
					unless absPartSize.is_a?(Snap)
						returns << [ V3[0,sumAbsPartSize,0], V3._0, Box.new(V3[scope.x,absPartSize,scope.z]) ]
						sumAbsPartSize += absPartSize
					else
						returns << [ V3[0,sumAbsPartSize,0], V3[-90,0,0], SnapPlaneRectangle.new(absPartSize, V2[scope.x*1.1,scope.z*1.1]) ]
					end
				}
			elsif axis == ZAxis
				sumAbsPartSize = 0
				absPartSizes.each{ |absPartSize|
					unless absPartSize.is_a?(Snap)
						returns << [ V3[0,0,sumAbsPartSize], V3._0, Box.new(V3[scope.x,scope.y,absPartSize]) ]
						sumAbsPartSize += absPartSize
					else
						returns << [ V3[0,0,sumAbsPartSize], V3._0, SnapPlaneRectangle.new(absPartSize, V2[scope.x*1.1,scope.y*1.1]) ]
					end
				}
			end
			returns
		end
	end

	class ::Shapes::Cylinder < Shape3D
	end

	class ::Shapes::TriangularPrism < Shape3D
		def componentFront; [ V3._0, V3[Math.atan2(scope.z/2.0,Float(scope.y))*180/Math::PI,0,0], Rectangle.new(V2[scope.x,Math.sqrt(scope.y*scope.y+(scope.z/2.0)*(scope.z/2.0))]) ]; end

		def componentBack; [ V3[scope.x,0,scope.z], V3[-Math.atan2(scope.z/2.0,Float(scope.y))*180/Math::PI,180,0], Rectangle.new(V2[scope.x,Math.sqrt(scope.y*scope.y+(scope.z/2.0)*(scope.z/2.0))]) ]; end

		def componentLeft; [ V3[0,0,scope.z], V3[0,90,0], IsoscelesTriangle.new(V2[scope.z,scope.y]) ]; end

		def componentRight; [ V3[scope.x,0,0], V3[0,-90,0], IsoscelesTriangle.new(V2[scope.z,scope.y]) ]; end

		def component( splitType )
			if splitType == SideFaces
				[ componentLeft, componentRight ]
			elsif splitType == MainFaces
				[ componentFront, componentBack ]
			else
				[ componentFront, componentBack, componentLeft, componentRight ]
			end
		end
	end

end
