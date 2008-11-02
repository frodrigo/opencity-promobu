require 'promobu/procedural-building-generator.rb'
include ProcedureBuildingGenerator

require 'promobu/shapes.rb'
include Shapes

require 'promobu/rules.rb'
include Rules

require 'promobu/faces.rb'
include Faces

require 'promobu/snaps.rb'
include Snaps

require 'promobu/exportX3D.rb'
require 'promobu/exportSVG.rb'
require 'promobu/optimize.rb'

def test1
	rulesSet = RulesSet.new()

	#root = Node.new( nil, "root", Box.new(V3[1,1,1]), V3._0, V3._0 )
	rulesSet << Rule.new( "root", nil, [Component.new(SideFaces,["d"])] )
	rulesSet << Rule.new( "d", nil, [Split.new(XAxis,[[AbsoluteSize.new(0.25),"e"],[RelativeSize.new(1),"f"]])] )
	rulesSet
end


def test2
	wallTexture = BindTexture.new(TiledTexture.new("canary/wall.png", 0.2, 0.5))

	rulesSet = RulesSet.new()

	#root = Node.new( nil, "root", Box.new(V3[5,5,3]), V3._0, V3._0 )
	rulesSet << Rule.new( "root", nil, [Scope.new(V3[2,2,2]), SubContext.new([Translation.new(V3[1,1,0]), Instantiate.new(Cylinder,"b")]), Instantiate.new(Cylinder,"b")] )
	rulesSet << Rule.new( "b", nil, [Scope.new(V3[1,1,1]), Instantiate.new(Box,"c")] )
	rulesSet << Rule.new( "c", nil, [Component.new(SideFaces,["d"])] )
	rulesSet << Rule.new( "d", nil, [Split.new(XAxis,[[AbsoluteSize.new(0.25),"e"],[RelativeSize.new(1),"f"]])] )
	rulesSet << Rule.new( "f", nil, [Tile.new(XAxis,0.25,"g")] )
	rulesSet << Rule.new( "g", nil, [wallTexture] )
	rulesSet
end

def testCanary
	wallTexture = BindTexture.new(TiledTexture.new("canary/wall.png", 0.2, 0.5))
	wallBottomTexture = BindTexture.new(TiledTexture.new("canary/wall-bottom.png", 0.5, 0.16))
	roofTexture = BindTexture.new(TiledTexture.new("canary/roof.png", 2, 1.67705098312484))

	rulesSet = RulesSet.new()

	#root = Node.new( nil, "root", Box.new(V3[8,5,3]), V3._0, V3._0 )
	rulesSet << Rule.new( "delete", nil, [Instantiate.new(Empty,nil)] )
	rulesSet << Rule.new( "root", nil, [Split.new(XAxis,[[AbsoluteSize.new(1),"border1"],[RelativeSize.new(1),"center"],[AbsoluteSize.new(1),"border1"]])] )
	rulesSet << Rule.new( "border1", nil, [Split.new(YAxis,[[RelativeSize.new(1),"border2"],[AbsoluteSize.new(0.5),"delete"]])] )
	rulesSet << Rule.new( "border2", nil, [Split.new(ZAxis,[[AbsoluteSize.new(0.1),"delete"],[RelativeSize.new(1),"border3"],[AbsoluteSize.new(0.1),"delete"]])] )
	rulesSet << Rule.new( "border3", nil, [Component.new(SideFaces,["levels"]),Component.new(TopFace,["roof"])] )
	rulesSet << Rule.new( "center", nil, [Component.new(SideFaces,["wallc"]),Component.new(TopFace,["roof"])] )
	rulesSet << Rule.new( "wallc", nil, [Split.new(YAxis,[[AbsoluteSize.new(1),"groundFloor"],[RelativeSize.new(1),"levels"]])] )
	rulesSet << Rule.new( "groundFloor", Proc.new{|node| node.queryAbsRotation?(V3._0)}, [Split.new(XAxis,[[RelativeSize.new(1),"level"],Snap.new("entrance",0.5),[AbsoluteSize.new(1.5),"door"],Snap.new("entrance",0.5),[RelativeSize.new(1),"level"]])] )
	rulesSet << Rule.new( "groundFloor", nil, [I.new("level")])
	rulesSet << Rule.new( "levels", nil, [Tile.new(YAxis,1,"level")] )
	rulesSet << Rule.new( "level", Proc.new{|node| node.shape.scope.x >= 1}, [Tile.new(XAxis,0.8,"window",nil,"entrance")] )
	rulesSet << Rule.new( "level", nil, [I.new("wb")] )
	rulesSet << Rule.new( "window", nil, [Split.new(YAxis,[[AbsoluteSize.new(0.3),"wb"],[RelativeSize.new(1),"wc"],[AbsoluteSize.new(0.2),"wb"]])] )
	rulesSet << Rule.new( "door", nil, [BindTexture.new(AdaptedTexture.new("canary/door.png"))] )
	rulesSet << Rule.new( "wb", nil, [wallTexture] )
	rulesSet << Rule.new( "wc", nil, [Split.new(XAxis,[[AbsoluteSize.new(0.2),"wb"],[RelativeSize.new(1),"ww"],[AbsoluteSize.new(0.2),"wb"]])] )
	rulesSet << Rule.new( "ww", nil, [BindTexture.new(AdaptedTexture.new("canary/window1.png"))] )
	rulesSet << Rule.new( "roof", nil, [Roof.new(GabledRoof,"roofShape")] )
	rulesSet << Rule.new( "roofShape", nil, [Component.new(MainFaces,["roofp"]),Component.new(SideFaces,["wb"])] )
	rulesSet << Rule.new( "roofp", nil, [roofTexture] )

	rulesSet
end

def testTTD
	cornerTexture = BindTexture.new(TiledTexture.new("ttd/corner.png", 1, 1))
	ornementTexture = BindTexture.new(TiledTexture.new("ttd/ornement.png", 1, 1))
	roofTexture = BindTexture.new(TiledTexture.new("ttd/roof.png", 2, 2))

	rulesSet = RulesSet.new()

	rulesSet << Rule.new("delete", nil, [Instantiate.new(Empty,nil)])

	rulesSet << Rule.new("root", nil, [Split.new(YAxis, [[AbsoluteSize.new(1.2),"groundLevel0"], [AbsoluteSize.new(1),"groundLevelOrnement"], [RelativeSize.new(3),"MainLevels"], [RelativeSize.new(5),"UpperLevels0"]])])

	rulesSet << Rule.new("groundLevelOrnement", nil, [Component.new(SideFaces, ["Ornement"])])

	rulesSet << Rule.new("groundLevel0", nil, [Component.new(RightFace,["ColumnLine0"]), Component.new(LeftFace,["ColumnLine0"]), Split.new(XAxis,[[AbsoluteSize.new(1),"delete"],[RelativeSize.new(1),"groundLevel1"],[AbsoluteSize.new(1),"delete"]])])
	rulesSet << Rule.new("groundLevel1", nil, [Split.new(ZAxis, [[RelativeSize.new(1),"groundLevel2"],[AbsoluteSize.new(1),"delete"]])])
	rulesSet << Rule.new("groundLevel2", nil, [Component.new(SideFaces, ["LevelWindows"])])

	rulesSet << Rule.new("ColumnLine0", nil, [Split.new(XAxis,[[RelativeSize.new(1),"ColumnLine1"],[AbsoluteSize.new(0.4),"Column0"]])])
	rulesSet << Rule.new("ColumnLine1", nil, [Tile.new(XAxis,1,"ColumnSpace")])
	rulesSet << Rule.new("ColumnSpace", nil, [Split.new(XAxis,[[AbsoluteSize.new(0.4),"Column0"],[RelativeSize.new(1),"delete"]])])
	rulesSet << Rule.new("Column0", nil, [Scope.new(Proc.new{|scope| V3[0.4,scope.y,0.3]}),Instantiate.new(Box,"Column1")])
	rulesSet << Rule.new("Column1", nil, [Component.new(SideFaces,["Column2"])])

	rulesSet << Rule.new("UpperLevels0", nil, [Split.new(XAxis, [[RelativeSize.new(1),"UpperLevels2"], [RelativeSize.new(1),"UpperLevels2"]])])
	rulesSet << Rule.new("UpperLevels2", nil, [Split.new(ZAxis, [[RelativeSize.new(1),"UpperLevels3"], [RelativeSize.new(1),"UpperLevels3"]])])
	rulesSet << Rule.new("UpperLevels3", nil, [Scope.new(Proc.new{|scope| scope+V3[0,-rand(scope.y/2),0]}),I.new("MainLevels")])

	rulesSet << Rule.new("MainLevels", nil, [Component.new(SideFaces, ["MainLevelsFaces"]),Component.new(TopFace, ["Roof"])])

	rulesSet << Rule.new("MainLevelsFaces", nil, [Split.new(YAxis, [[RelativeSize.new(1),"MainLevelsWindows"], [AbsoluteSize.new(0.5),"Ornement"]])])

	rulesSet << Rule.new("MainLevelsWindows", nil, [Tile.new(YAxis,1,"Level")])
	rulesSet << Rule.new("Level", nil, [Split.new(XAxis,[[AbsoluteSize.new(1),"LevelCorner"],[RelativeSize.new(1),"LevelWindows"],[AbsoluteSize.new(1),"LevelCorner"]])])

	rulesSet << Rule.new("LevelWindows", nil, [Tile.new(XAxis, 0.5, "Window")])

	rulesSet << Rule.new("Column2", nil, [ornementTexture])
	rulesSet << Rule.new("Window", nil, [BindTexture.new(AdaptedTexture.new("ttd/window.png"))])
	rulesSet << Rule.new("LevelCorner", nil, [cornerTexture])
	rulesSet << Rule.new("Ornement", nil, [ornementTexture])
	rulesSet << Rule.new("Roof", nil, [roofTexture])

	rulesSet
end


root = Node.new( nil, "root", Box.new(V3[10,30,10]), V3._0, V3._0 )

#testCanary.apply( [root] )
testTTD.apply( [root] )
#SnapRegistery.instance.parallel(V3[0,0,1])
#puts SnapRegistery.instance.nearestSnapPlane(V3[1.4,0,0],V3[0,0,1])

#print root.to_s() + "\n"

root = Optimize::optimize( root )

ExportX3D::export( root, "out.x3d" )
