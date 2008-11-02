
module ProcedureBuildingGenerator
	class Node
		def exportSVGDef( node )
			shape.exportSVGDef( node )
		end

		def exportSVG( node )
			node = node.add_element("svg:g", {
				"transform"=>"translate(#{position.x},#{position.y})" } )
			shape.exportSVG( node )
		end
	end

	class AdaptedTexture < Texture
		def idSVG( id )
			id
		end

		@@size = {
			"canary/window1.png"=>V2[40,40],
			"canary/door.png"=>V2[60,129],
			"ttd/window.png"=>V2[64,128]
		}

		def exportSVGDef( node, w, h, id )
		end

		def exportSVG( node, w, h, id )
			textureW = @@size[textureFile].x
			textureH = @@size[textureFile].y
			node.add_element("svg:pattern", {
				"id"=>idSVG( id ),
				"patternUnits"=>"userSpaceOnUse",
				"width"=>textureW,
				"height"=>textureH,
				"patternTransform"=>"matrix(#{w/(Float textureW)},0,0,#{-h/(Float textureH)},0,0)" }).add_element("image", {
					"xlink:href"=>textureFile,
					"width"=>textureW,
					"height"=>textureH } )
		end
	end

	class TiledTexture < Texture
		def idSVG( id )
			"pattern-#{textureFile.object_id}"
		end

		@@size = {
			"canary/wall.png"=>V2[53,135],
			"canary/wall-bottom.png"=>V2[50,16],
			"canary/roof.png"=>V2[255,129],
			"ttd/corner.png"=>V2[96,96],
			"ttd/ornement.png"=>V2[120,120],
			"ttd/roof.png"=>V2[128,128]
		}

		@@exportSVG = {}

		def exportSVGDef( node, w, h, id )
			if @@exportSVG[object_id] != node then
				textureW = @@size[textureFile].x
				textureH = @@size[textureFile].y
				node.add_element("svg:pattern", {
					"id"=>idSVG( id ),
					"patternUnits"=>"userSpaceOnUse",
					"width"=>textureW,
					"height"=>textureH,
					"patternTransform"=>"matrix(#{self.w/(Float textureW)},0,0,#{-self.h/(Float textureH)},0,0)" }).add_element("image", {
						"xlink:href"=>textureFile,
						"width"=>textureW,
						"height"=>textureH } )
				@@exportSVG[object_id] = node
			end
		end

		def exportSVG( node, w, h, id )
		end
	end
end

module Shapes
	class ::Shapes::Shape2D < Shape
		def exportSVGDef( node )
			if texture != nil then
				texture.exportSVGDef( node, scope.x, scope.y, "pattern-#{self.object_id}" )
			end
		end

		def exportSVG( node )
			if texture != nil then
				texture.exportSVG( node, scope.x, scope.y, "pattern-#{self.object_id}" )
			end
		end
	end

	class ::Shapes::Rectangle < Shape2D
		def exportSVGDef( node )
			super( node )
		end

		def exportSVG( node )
			super( node )
			node.add_element("svg:rect", {
				"id"=>"rect-#{self.object_id}",
				"width"=>scope.x,
				"height"=>scope.y }.merge(
				texture ? { "style"=> "fill:url(##{texture.idSVG("pattern-#{self.object_id}")})" } : {}) )
		end
	end

	class ::Shapes::IsoscelesTriangle < Shape2D
		def exportSVGDef( node )
			super( node )
		end

		def exportSVG( node )
			super( node )
			node.add_element("svg:path", {
				"d"=>"M #{0},#{0} L #{scope.x},#{0} L #{scope.x / 2.0},#{scope.y} z",
				"id"=>"rect-#{self.object_id}" }.merge(
				texture ? { "style"=> "fill:url(##{texture.idSVG("pattern-#{self.object_id}")})" } : {}) )
		end
	end
end

module Optimize
	class ::Optimize::AggregatedTexture
		def exportSVG
			svg = REXML::Document.new()
			svg.add(REXML::XMLDecl.new(REXML::XMLDecl::DEFAULT_VERSION,REXML::XMLDecl::DEFAULT_ENCODING,"no"))
			svgRoot = svg.add_element("svg", {
				"xmlns"=>"http://www.w3.org/2000/svg",
				"xmlns:svg"=>"http://www.w3.org/2000/svg",
				"xmlns:xlink"=>"http://www.w3.org/1999/xlink",
				"width"=>self.w,
				"height"=>self.h} )
			svgDefs = svgRoot.add_element("svg:defs", {} )
			self.tiles.each { |pr,node|
				node.exportSVGDef( svgDefs )
			}
			svgRoot = svgRoot.add_element("svg:g", {
				"transform"=>"matrix(1,0,0,-1,0,#{self.h})" } )
			self.tiles.each { |pr,node|
				node.position = pr[0]
				node.rotation = pr[1]
				node.exportSVG( svgRoot )
			}
			svg.write(File.new(self.file+".svg", "w"),2)
		end
	end
end
