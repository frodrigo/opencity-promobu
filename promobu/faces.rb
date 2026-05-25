
module Faces

	class ::Faces::ShapeSplit
	end

	class ::Faces::Face < ShapeSplit
	end

	class ::Faces::AllFaces < Face
	end

	class ::Faces::BottomFace < Face
	end

	class ::Faces::TopFace < Face
	end

	class ::Faces::SideFaces < Face
	end

	class ::Faces::RightFace < Face
	end

	class ::Faces::LeftFace < Face
	end

	class ::Faces::FrontFace < Face
	end

	class ::Faces::BackFace < Face
	end

	class ::Faces::MainFaces < Face
	end

	class ::Faces::ReverseFrontFace  < Face; end
	class ::Faces::ReverseBackFace   < Face; end
	class ::Faces::ReverseLeftFace   < Face; end
	class ::Faces::ReverseRightFace  < Face; end
	class ::Faces::ReverseTopFace    < Face; end
	class ::Faces::ReverseBottomFace < Face; end
	class ::Faces::ReverseSideFaces  < Face; end
	class ::Faces::ReverseAllFaces   < Face; end

	class ::Faces::Roof_
	end

	class ::Faces::GambrelRoof < Roof_
	end

	class ::Faces::GabledRoof < Roof_
	end

	class ::Faces::HippedRoof < Roof_
	end

	class ::Faces::MansardRoof < Roof_
	end

end
