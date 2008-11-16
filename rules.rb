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
require 'promobu/exportAC3D.rb'
require 'promobu/exportSVG.rb'
require 'promobu/optimize.rb'

def test1
	rulesSet = RulesSet.new()

	rulesSet << Rule.new( "root", nil, [Component.new(SideFaces,["d"])] )
	rulesSet << Rule.new( "d", nil, [Split.new(XAxis,SplitElement.new([[AbsoluteSize.new(0.25),"e"],[RelativeSize.new(1),"f"]]))] )
	rulesSet
end

def test2
	wallTexture = BindTexture.new(TiledTexture.new("canary/wall.png", 0.2, 0.5))

	rulesSet = RulesSet.new()

	rulesSet << Rule.new( "root", nil, [Scope.new(V3[2,2,2]), SubContext.new([Translation.new(V3[1,1,0]), Instantiate.new(Cylinder,"b")]), Instantiate.new(Cylinder,"b")] )
	rulesSet << Rule.new( "b", nil, [Scope.new(V3[1,1,1]), Instantiate.new(Box,"c")] )
	rulesSet << Rule.new( "c", nil, [Component.new(SideFaces,["d"])] )
	rulesSet << Rule.new( "d", nil, [Split.new(XAxis, SplitElement.new([[AbsoluteSize.new(0.25),"e"],[RelativeSize.new(1),"f"]]))] )
	rulesSet << Rule.new( "f", nil, [Split.new(XAxis,SplitRepeat(0.25,"g"))] )
	rulesSet << Rule.new( "g", nil, [wallTexture] )
	rulesSet
end

def testCanary
	wallTexture = BindTexture.new(TiledTexture.new("canary/wall.png", 0.2, 0.5))
	wallBottomTexture = BindTexture.new(TiledTexture.new("canary/wall-bottom.png", 0.5, 0.16))
	roofTexture = BindTexture.new(TiledTexture.new("canary/roof.png", 2, 1.67705098312484))

	rulesSet = RulesSet.new()

	rulesSet << Rule.new( "delete", nil, [Instantiate.new(Empty,nil)] )
	rulesSet << Rule.new( "root", nil, [Split.new(XAxis,SplitElement.new([
		[AbsoluteSize.new(1), "border1"],
		[RelativeSize.new(1), "center"],
		[AbsoluteSize.new(1), "border1"]]))] )
	rulesSet << Rule.new( "border1", nil, [Split.new(YAxis,SplitElement.new([
		[RelativeSize.new(1), "border2"],
		[AbsoluteSize.new(0.7), "delete"]]))] )
	rulesSet << Rule.new( "border2", nil, [Split.new(ZAxis,SplitElement.new([
		[AbsoluteSize.new(0.1), "delete"],
		[RelativeSize.new(1), "border3"],
		[AbsoluteSize.new(0.1), "delete"]]))] )
	rulesSet << Rule.new( "border3", nil, [Component.new(SideFaces,["levels"]),Component.new(TopFace,["roof"])] )
	rulesSet << Rule.new( "center", nil, [Component.new(SideFaces,["wallc"]),Component.new(TopFace,["roof"])] )
	rulesSet << Rule.new( "wallc", nil, [Split.new(YAxis,SplitElement.new([
		[AbsoluteSize.new(1), "groundFloor"],
		Snap.new("level",0.5),
		[RelativeSize.new(1), "levels"]]))] )
	rulesSet << Rule.new( "groundFloor", Proc.new{|node| node.queryAbsRotation?(V3._0)}, [Split.new(XAxis,SplitElement.new([
		[RelativeSize.new(1), "level"],
		Snap.new("entrance",0.5),
		[AbsoluteSize.new(1.5), "door"],
		Snap.new("entrance",0.5),
		[RelativeSize.new(1), "level"]]))] )
	rulesSet << Rule.new( "groundFloor", nil, [I.new("level")])
	rulesSet << Rule.new( "levels", nil, [Split.new(YAxis,SplitRepeat.new(1,"level",Snap.new("level",0.5),"level"))] )
	rulesSet << Rule.new( "level", Proc.new{|node| node.shape.scope.x >= 1 and node.shape.scope.y >= 0.8}, [Split.new(XAxis,SplitRepeat.new(0.8,"window",nil,"entrance"))] )
	rulesSet << Rule.new( "level", nil, [I.new("wb")] )
	rulesSet << Rule.new( "window", nil, [Split.new(YAxis,SplitElement.new([
		[AbsoluteSize.new(0.3), "wb"],
		[RelativeSize.new(1), "wc"],
		[AbsoluteSize.new(0.2), "wb"]]))] )
	rulesSet << Rule.new( "wc", nil, [Split.new(XAxis,SplitElement.new([
		[AbsoluteSize.new(0.2), "wb"],
		[RelativeSize.new(1), "ww"],
		[AbsoluteSize.new(0.2), "wb"]]))] )
	rulesSet << Rule.new( "roof", nil, [Roof.new(GabledRoof,"roofShape")] )
	rulesSet << Rule.new( "roofShape", nil, [Component.new(MainFaces,["roofp"]),Component.new(SideFaces,["wb"])] )
	
	rulesSet << Rule.new( "door", nil, [BindTexture.new(AdaptedTexture.new("canary/door.png"))] )
	rulesSet << Rule.new( "ww", nil, [BindTexture.new(AdaptedTexture.new("canary/window1.png"))] )
	rulesSet << Rule.new( "roofp", nil, [roofTexture] )
	rulesSet << Rule.new( "wb", nil, [wallTexture] )

	rulesSet
end

def testTTD
	cornerTexture = BindTexture.new(TiledTexture.new("ttd/corner.png", 1, 1))
	ornementTexture = BindTexture.new(TiledTexture.new("ttd/ornement.png", 1, 1))
	roofTexture = BindTexture.new(TiledTexture.new("ttd/roof.png", 2, 2))

	rulesSet = RulesSet.new()

	rulesSet << Rule.new("delete", nil, [Instantiate.new(Empty,nil)])

	rulesSet << Rule.new("root", nil, [Split.new(YAxis, SplitElement.new([
		[AbsoluteSize.new(1.2), "groundLevel0"],
		[AbsoluteSize.new(1), "groundLevelOrnement"],
		[RelativeSize.new(3), "MainLevels"],
		[RelativeSize.new(5), "UpperLevels0"]]))])

	rulesSet << Rule.new("groundLevelOrnement", nil, [Component.new(SideFaces, ["Ornement"])])

	rulesSet << Rule.new("groundLevel0", nil, [Component.new(RightFace,["ColumnLine0"]), Component.new(LeftFace,["ColumnLine0"]), Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(1), "delete"],
		[RelativeSize.new(1),"groundLevel1"],
		[AbsoluteSize.new(1),"delete"]]))])
	rulesSet << Rule.new("groundLevel1", nil, [Split.new(ZAxis, SplitElement.new([
		[RelativeSize.new(1), "groundLevel2"],
		[AbsoluteSize.new(1), "delete"]]))])
	rulesSet << Rule.new("groundLevel2", nil, [Component.new(SideFaces, ["Level"])])

	rulesSet << Rule.new("ColumnLine0", nil, [Split.new(XAxis, SplitElement.new([
		[RelativeSize.new(1), SplitRepeat.new(1, SplitElement.new([
			[AbsoluteSize.new(0.4), "Column0"],
			[RelativeSize.new(1), "delete"]]))],
		[AbsoluteSize.new(0.4), "Column0"]]))])
	rulesSet << Rule.new("Column0", nil, [Scope.new(Proc.new{|scope| V3[0.4,scope.y,0.3]}),Instantiate.new(Box,"Column1")])
	rulesSet << Rule.new("Column1", nil, [Component.new(SideFaces,["Column2"])])

	rulesSet << Rule.new("UpperLevels0", nil, [Split.new(XAxis, SplitElement.new([[RelativeSize.new(1),"UpperLevels2"], [RelativeSize.new(1),"UpperLevels2"]]))])
	rulesSet << Rule.new("UpperLevels2", nil, [Split.new(ZAxis, SplitElement.new([[RelativeSize.new(1),"UpperLevels3"], [RelativeSize.new(1),"UpperLevels3"]]))])
	rulesSet << Rule.new("UpperLevels3", nil, [Scope.new(Proc.new{|scope| scope+V3[0,-rand(scope.y / 2),0]}),I.new("MainLevels")])

	rulesSet << Rule.new("MainLevels", nil, [Component.new(SideFaces, ["MainLevelsFaces"]),Component.new(TopFace, ["Roof"])])

	rulesSet << Rule.new("MainLevelsFaces", nil, [Split.new(YAxis, SplitElement.new([
		[RelativeSize.new(1), "MainLevelsWindows"],
		[AbsoluteSize.new(0.5), "Ornement"]]))])

	rulesSet << Rule.new("MainLevelsWindows", nil, [Split.new(YAxis,SplitRepeat.new(1,"Level"))])
	rulesSet << Rule.new("Level", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(1), "LevelCorner"],
		[RelativeSize.new(1), SplitRepeat.new(0.5, "Window")],
		[AbsoluteSize.new(1), "LevelCorner"]]))])

	rulesSet << Rule.new("Column2", nil, [ornementTexture])
	rulesSet << Rule.new("Window", nil, [BindTexture.new(AdaptedTexture.new("ttd/window.png"))])
	rulesSet << Rule.new("LevelCorner", nil, [cornerTexture])
	rulesSet << Rule.new("Ornement", nil, [ornementTexture])
	rulesSet << Rule.new("Roof", nil, [roofTexture])

	rulesSet
end

def testNYC1920
	rulesSet = RulesSet.new()

	rulesSet << Rule.new("delete", nil, [Instantiate.new(Empty,nil)])

	rulesSet << Rule.new("root", nil, [Split.new(YAxis, SplitElement.new([
		[AbsoluteSize.new(2.5), "groundLevel0"],
		[AbsoluteSize.new(0.3), "groundLevelFrise0"],
		[AbsoluteSize.new(0.9), "frise0"],
		[AbsoluteSize.new(0.1), "frise0frise0"],
		[RelativeSize.new(1), "MainLevels"],
		[AbsoluteSize.new(1.3), "LastMainLevel"],
		[AbsoluteSize.new(0.1), "topFrise0frise00"],
		[AbsoluteSize.new(1.1), "topFrise0"],
		[AbsoluteSize.new(0.3), "roof0"],
		[AbsoluteSize.new(1.2), "balcon0"]]))])

	# GroundLevel
	rulesSet << Rule.new("groundLevel0", nil, [Component.new(SideFaces, ["groundLevel0face"])])
	rulesSet << Rule.new("groundLevel0face", Proc.new{|node| node.queryAbsRotation?(V3._0)}, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(2.5), "groundLevel0BigDoor"],
		[RelativeSize.new(1), SplitRepeat.new(2, SplitElement.new([
			[AbsoluteSize.new(1.8), "groundLevel0Door2Door"],
			[RelativeSize.new(1), "groundLevel0Door2DoorColumn"]]))],
		[AbsoluteSize.new(1.8), "groundLevel0Door2Door"],
		[AbsoluteSize.new(2.5), "groundLevel0BigDoor"]]))])
	rulesSet << Rule.new("groundLevel0face", nil, [Split.new(XAxis, SplitElement.new([
		[RelativeSize.new(1), "groundLevel0Door2DoorColumn"],
		[RelativeSize.new(1), SplitRepeat.new(2, SplitElement.new([
			[AbsoluteSize.new(1.8), "groundLevel0Door2Door"],
			[RelativeSize.new(1), "groundLevel0Door2DoorColumn"]]))]]))])

	# GroundLevel BigDoor
	rulesSet << Rule.new("groundLevel0BigDoor", nil, [Scope.new(Proc.new{|scope| V3[scope.x,scope.y,0.4]}), Translation.new(V3[0,0,-0.4]), Instantiate.new(Box,"BigDoor0")])
	rulesSet << Rule.new("BigDoor0", nil, [Component.new(FrontFace, ["groundLevel0Door2"]), Component.new(RightFace, ["groundLevel0Door2DoorColumn2"]), Component.new(LeftFace, ["groundLevel0Door2DoorColumn2"])])

	# GroundLevel Door
	rulesSet << Rule.new("groundLevel0Door2", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.5), "groundLevel0Door2DoorColumn"],
		[RelativeSize.new(1), "groundLevel0Door2Door"],
		[AbsoluteSize.new(0.5), "groundLevel0Door2DoorColumn"]]))])

	# GroundLevel column
	rulesSet << Rule.new("groundLevel0Door2DoorColumn", nil, [Scope.new(Proc.new{|scope| V3[scope.x,scope.y,0.2]}), Translation.new(V3[0,0,-0.2]), Instantiate.new(Box,"groundLevel0Door2DoorColumn1")])
	rulesSet << Rule.new("groundLevel0Door2DoorColumn1", nil, [Component.new(FrontFace, ["groundLevel0Door2DoorColumn2"]), Component.new(RightFace,["groundLevel0Door2DoorColumn2"]), Component.new(LeftFace,["groundLevel0Door2DoorColumn2"])])

	rulesSet << Rule.new("groundLevelFrise0", nil, [Scope.new(Proc.new{ |scope| scope+V3[0.4,0,0.4] }), Translation.new(V3[-0.2,0,-0.2]), I.new("groundLevelFrise1")])
	rulesSet << Rule.new("groundLevelFrise1", nil, [Component.new(AllFaces, ["groundLevelFriseFace"])])

	# MainLevel
	rulesSet << Rule.new("MainLevels", nil, [Split.new(YAxis, SplitRepeat.new(1, "MainLevel0"))])
	rulesSet << Rule.new("MainLevel0", nil, [Component.new(SideFaces, ["MainLevelFace0"])])
	rulesSet << Rule.new("MainLevelFace0", Proc.new{|node| node.queryAbsRotation?(V3._0)}, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(2.5), "MainLevel0Border"],
		[RelativeSize.new(1), SplitRepeat.new(2, SplitElement.new([
			[AbsoluteSize.new(1.8), "MainLevel0CenterWindows2"],
			[RelativeSize.new(1), "MainLevel0CenterColumn"]]))],
		[AbsoluteSize.new(1.8), "MainLevel0CenterWindows2"],
		[AbsoluteSize.new(2.5), "MainLevel0Border"]]))])
	rulesSet << Rule.new("MainLevel0Border", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.5), "MainLevel0BorderWall"],
		[RelativeSize.new(1), "MainLevel0BorderWindows2"],
		[AbsoluteSize.new(0.5), "MainLevel0BorderWall"]]))])
	rulesSet << Rule.new("MainLevelFace0", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.5), "MainLevel0BorderWall"],
		[RelativeSize.new(1), SplitRepeat.new(2.5, SplitElement.new([
			[RelativeSize.new(1), "MainLevel0BorderWindows2"],
			[AbsoluteSize.new(0.5), "MainLevel0BorderWall"]]))]]))])

	# LastMainLevel
	rulesSet << Rule.new("LastMainLevel", nil, [Component.new(SideFaces, ["LastMainLevelFace0"])])
	rulesSet << Rule.new("LastMainLevelFace0", Proc.new{|node| node.queryAbsRotation?(V3._0)}, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(2.5), "LastMainLevel0Border"],
		[RelativeSize.new(1), SplitRepeat.new(2, SplitElement.new([
			[AbsoluteSize.new(1.8), "LastMainLevel0CenterWindows2"],
			[RelativeSize.new(1), "LastMainLevel0CenterColumn"]]))],
		[AbsoluteSize.new(1.8), "LastMainLevel0CenterWindows2"],
		[AbsoluteSize.new(2.5), "LastMainLevel0Border"]]))])
	rulesSet << Rule.new("LastMainLevel0Border", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.5), "LastMainLevel0BorderWall"],
		[RelativeSize.new(1), "LastMainLevel0BorderWindows2"],
		[AbsoluteSize.new(0.5), "LastMainLevel0BorderWall"]]))])
	rulesSet << Rule.new("LastMainLevelFace0", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.5), "LastMainLevel0BorderWall"],
		[RelativeSize.new(1), SplitRepeat.new(2.5, SplitElement.new([
			[RelativeSize.new(1), "LastMainLevel0BorderWindows2"],
			[AbsoluteSize.new(0.5), "LastMainLevel0BorderWall"]]))]]))])

	rulesSet << Rule.new("frise0", nil, [Component.new(SideFaces, ["frise0face"])])
	rulesSet << Rule.new("frise0face", nil, [Split.new(YAxis, SplitElement.new([
		[RelativeSize.new(1), "frise0windows"],
		[AbsoluteSize.new(0.1), "frise0wall"]]))])
	rulesSet << Rule.new("frise0windows", Proc.new{|node| node.queryAbsRotation?(V3._0)}, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(2.5), "frise0windwosBorder"],
		[RelativeSize.new(1), SplitRepeat.new(2, SplitElement.new([
			[AbsoluteSize.new(1.8), "frise0windwosWindows2"],
			[RelativeSize.new(1), "frise0windwosBlason"]]))],
		[AbsoluteSize.new(1.8), "frise0windwosWindows2"],
		[AbsoluteSize.new(2.5), "frise0windwosBorder"]]))])
	rulesSet << Rule.new("frise0windwosBorder", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.5), "frise0windwosBorderSatus"],
		[RelativeSize.new(1), "frise0windwosWindows2"],
		[AbsoluteSize.new(0.5), "frise0windwosBorderSatus"]]))])
	rulesSet << Rule.new("frise0windows", nil, [Split.new(XAxis, SplitElement.new([
		[RelativeSize.new(1), "frise0windwosBlason"],
		[RelativeSize.new(1), SplitRepeat.new(2, SplitElement.new([
			[AbsoluteSize.new(1.8), "frise0windwosWindows2"],
			[RelativeSize.new(1), "frise0windwosBlason"]]))]]))])

	rulesSet << Rule.new("topFrise0", nil, [Component.new(SideFaces, ["topFrise0face"])])
	rulesSet << Rule.new("topFrise0face", nil, [Split.new(YAxis, SplitElement.new([
		[RelativeSize.new(1), "topFrise0windows0"],
		[AbsoluteSize.new(0.3), "topFrise0frise1"]]))])
	rulesSet << Rule.new("topFrise0windows0", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.4), "topFrise0windows0box"],
		[RelativeSize.new(1), SplitRepeat.new(1, SplitElement.new([
			[RelativeSize.new(1), "topFrise0windows0window"],
			[AbsoluteSize.new(0.4), "topFrise0windows0box"]]))]]))])

	rulesSet << Rule.new("balcon0", nil, [Component.new(SideFaces, ["balcon0face"])])
	rulesSet << Rule.new("balcon0face", nil, [Split.new(XAxis, SplitElement.new([
		[AbsoluteSize.new(0.3), "balcon0corner"],
		[AbsoluteSize.new(1), "balcon0join"],
		[RelativeSize.new(1), SplitRepeat.new(1.3, SplitElement.new([
			[RelativeSize.new(1),"balcon0column"],
			[AbsoluteSize.new(1),"balcon0join"]]))],
		[AbsoluteSize.new(0.3), "balcon0corner"]]))])

	rulesSet << Rule.new("frise0frise0", nil, [Scope.new(Proc.new{ |scope| scope+V3[0.4,0,0.4] }), Translation.new(V3[-0.2,0,-0.2]), I.new("frise0frise1")])
	rulesSet << Rule.new("frise0frise1", nil, [Component.new(AllFaces, ["frise0friseFace"])])

	rulesSet << Rule.new("topFrise0frise00", nil, [Scope.new(Proc.new{ |scope| scope+V3[0.4,0,0.4] }), Translation.new(V3[-0.2,0,-0.2]), I.new("topFrise0frise01")])
	rulesSet << Rule.new("topFrise0frise01", nil, [Component.new(AllFaces, ["topFrise0frise01Face"])])

	rulesSet << Rule.new("roof0", nil, [Scope.new(Proc.new{ |scope| scope+V3[0.8,0,0.8] }), Translation.new(V3[-0.4,0,-0.4]), I.new("roof1")])
	rulesSet << Rule.new("roof1", nil, [Component.new(AllFaces, ["roof0Face"])])

	rulesSet << Rule.new("balcon0", nil, [Component.new(SideFaces, ["balcon0face"])])

	rulesSet << Rule.new("groundLevel0Door2DoorColumn2", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/ground-column.png"))])
	rulesSet << Rule.new("groundLevel0Door2Door", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/ground-door.png"))])
	rulesSet << Rule.new("groundLevelFriseFace", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/ground-frise.png"))])

	rulesSet << Rule.new("MainLevel0CenterColumn", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-wall.png"))])
	rulesSet << Rule.new("MainLevel0BorderWall", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-wall.png"))])
	rulesSet << Rule.new("MainLevel0BorderWindows2", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-windows2.png"))])
	rulesSet << Rule.new("MainLevel0CenterWindows2", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-windows2c.png"))])

	rulesSet << Rule.new("LastMainLevel0CenterColumn", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-wall.png"))])
	rulesSet << Rule.new("LastMainLevel0BorderWall", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-wall.png"))])
	rulesSet << Rule.new("LastMainLevel0BorderWindows2", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-last-windows2.png"))])
	rulesSet << Rule.new("LastMainLevel0CenterWindows2", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/main-last-windows2c.png"))])

	rulesSet << Rule.new("frise0friseFace", nil, [BindTexture.new(TiledTexture.new("nyc1920/frise-frise.png", 18*0.1/12, 0.1))])
	rulesSet << Rule.new("frise0windwosWindows2", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/frise-windows2.png"))])
	rulesSet << Rule.new("frise0windwosBorderSatus", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/frise-status.png"))])
	rulesSet << Rule.new("frise0windwosBlason", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/frise-blason.png"))])
	rulesSet << Rule.new("frise0wall", nil, [BindTexture.new(TiledTexture.new("nyc1920/wall.png",13/55, 1))])

	rulesSet << Rule.new("topFrise0frise01Face", nil, [BindTexture.new(TiledTexture.new("nyc1920/top-frise-frise0.png", 47*0.1/9, 0.1))])
	rulesSet << Rule.new("topFrise0frise1", nil, [BindTexture.new(TiledTexture.new("nyc1920/top-frise-frise1.png", 83*0.1/29, 0.1))])
	rulesSet << Rule.new("topFrise0windows0box", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/top-frise-box.png"))])
	rulesSet << Rule.new("topFrise0windows0window", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/top-frise-window.png"))])

	rulesSet << Rule.new("roof0Face", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/roof-frise.png"))])

	rulesSet << Rule.new("balcon0corner", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/balcon-corner.png"))])
	rulesSet << Rule.new("balcon0join", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/balcon-join.png"))])
	rulesSet << Rule.new("balcon0column", nil, [BindTexture.new(AdaptedTexture.new("nyc1920/balcon-column.png"))])

	rulesSet
end


root = Node.new( nil, "root", Box.new(V3[5,3,4]), V3._0, V3._0 )
testCanary.apply( [root] )

#root = Node.new( nil, "root", Box.new(V3[10,30,10]), V3._0, V3._0 )
#testTTD.apply( [root] )

#root = Node.new( nil, "root", Box.new(V3[20,14,8]), V3._0, V3._0 )
#testNYC1920.apply( [root] )

#SnapRegistery.instance.parallel(V3[0,0,1])
#puts SnapRegistery.instance.nearestSnapPlane(V3[1.4,0,0],V3[0,0,1])

#print root.to_s() + "\n"

#root = Optimize::optimize( root )

#ExportX3D::export( root, "out.x3d" )
ExportAC3D::export( root, "out.ac" )
