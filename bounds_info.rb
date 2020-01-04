# Extract useful info from bounding boxes.
module BoundsInfo
  # List all 8 corners of the bounding box. The order is
  # bottom front left, bottom front right, bottom back left, bottom back right,
  # top front left, top front right, top back left, top back right.
  #
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
  #
  # @examples
  #   # Corners of the invisible box orthogonal to the drawing axes.
  #   BoundsInfo.corners(instance.bounds)
  #
  #   # Corners of visible selection box for an instance.
  #   BoundsInfo.corners(instance.definition.bounds, instance.transformation)
  #
  # @return [Array<Geom::Point3d>]
  def self.corners(bounds, tranformation = IDENTITY)
    Array.new(8) { |n| bounds.corner(n).transform(tranformation) }
  end

  # List all 12 lines of the bounding box.
  #
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
  #
  # @return [Array<Array<Geom::Point3d>]
  def self.lines(bounds, transformation = IDENTITY)
    corners = corners(bounds, transformation)

    [
      corners.values_at(0, 1),
      corners.values_at(1, 5),
      corners.values_at(0, 2),
      corners.values_at(2, 3),
      corners.values_at(0, 4),
      corners.values_at(4, 6),
      corners.values_at(7, 6),
      corners.values_at(6, 2),
      corners.values_at(7, 5),
      corners.values_at(5, 4),
      corners.values_at(7, 3),
      corners.values_at(3, 1)
    ]
  end

  # List the 6 sides of the bounds.
  # The order is right, back, top, left, front, bottom.
  #
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
  #
  # @return [Array<Array<Geom::Point3d>]
  def self.sides(bounds, transformation = IDENTITY)
    corners = corners(bounds, transformation)

    [
      corners.values_at(1, 3, 7, 5),
      corners.values_at(3, 2, 6, 7),
      corners.values_at(4, 5, 7, 6),
      corners.values_at(2, 0, 4, 6),
      corners.values_at(0, 1, 5, 4),
      corners.values_at(2, 3, 1, 0)
    ]
  end

  # List the 6 normals of the bounds.
  # The order is right, back, top, left, front, bottom.
  #
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
  #
  # @return [Array<Geom::Vector3d>]
  def self.normals(bounds, transformation = IDENTITY)
    [
      transformation.xaxis,
      transformation.yaxis,
      transformation.zaxis,
      transformation.xaxis.reverse,
      transformation.yaxis.reverse,
      transformation.zaxis.reverse
    ]
  end
end
