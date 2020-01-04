# Extract useful info from bounding boxes.
#
# Note that the bounds of an instance itself are invisible in SketchUp.
# Typically what you want is the transformed bounds of its definition.
#
# @examples
#   # Corners of the invisible bounds orthogonal to the drawing axes.
#   BoundsInfo.corners(instance.bounds)
#
#   # Corners of visible selection bounds for an instance.
#   BoundsInfo.corners(instance.definition.bounds, instance.transformation)
module BoundsInfo
  # Represents the intersection between a line and a bounding box.
  #
  # @!attribute position
  #   @return [Geom::Point3d]
  # @!attribute normal
  #   @return [Geom::Vector3d]
  # @!attribute distance
  #   @return [Length]
  #     Where along line bounds where intersected. Can be negative.
  #     Useful for identifying the front-most intersected bounds.
  # @!attribute side
  #   @return [Integer]
  #     0 = right, 1 = back, 2 = top, 3 = left, 4 = front, 5 = bottom.
  Intersection = Struct.new(:position, :normal, :distance, :side)

  # List all 8 corners of the bounding box. The order is
  # bottom front left, bottom front right, bottom back left, bottom back right,
  # top front left, top front right, top back left, top back right.
  #
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
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
      transform_as_normal(X_AXIS, transformation),
      transform_as_normal(Y_AXIS, transformation),
      transform_as_normal(Z_AXIS, transformation),
      transform_as_normal(X_AXIS.reverse, transformation),
      transform_as_normal(Y_AXIS.reverse, transformation),
      transform_as_normal(Z_AXIS.reverse, transformation),
    ]
  end

  # List the 6 planes of the bounds.
  # The order is right, back, top, left, front, bottom.
  #
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
  #
  # @return [Array<Array<(Geom::Point3d, Geom::Vector3d)>>]
  def self.planes(bounds, transformation = IDENTITY)
    corners = corners(bounds, transformation)
    normals = normals(bounds, transformation)

    [
      [corners[7], normals[0]],
      [corners[7], normals[1]],
      [corners[7], normals[2]],
      [corners[0], normals[3]],
      [corners[0], normals[4]],
      [corners[0], normals[5]],
    ]
  end

  # Find intersection between line and bounding box.
  #
  # @param line [Array<(Geom::Point3d, Geom::Vector3d)>]
  # @param bounds [Geom::BoundingBox]
  # @param transformation [Geom::Transformation]
  #
  # @return [Intersection]
  def self.intersect_line(line, bounds, transformation = IDENTITY)
    # REVIEW: Use struct for return values?

    line_transformation = Geom::Transformation.new(*line)
    sides = sides(bounds, line_transformation.inverse * transformation)
    index = sides.find_index { |s| facing?(s) && Geom.point_in_polygon_2D(ORIGIN, s, true) }
    return unless index

    plane = planes(bounds, transformation)[index]
    intersection = Geom.intersect_line_plane(line, plane)

    Intersection.new(
      intersection,
      plane[1],
      intersection.transform(line_transformation.inverse).z,
      index
    )
  end

  # Private

  def self.transform_as_normal(normal, transformation)
    tangent = normal.axes[0].transform(transformation)
    bi_tangent = normal.axes[1].transform(transformation)

    (tangent * bi_tangent).normalize
  end
  private_class_method :transform_as_normal

  def self.facing?(corners)
    polygon_normal(corners).z < 0
  end
  private_class_method :facing?

  # Find normal vector from an array of points representing a polygon.
  #
  # @param points [Array<Geom::Point3d>]
  #
  # @return [Geom::Vector3d]
  def self.polygon_normal(points)
    normal = Geom::Vector3d.new
    points.each_with_index do |pt0, i|
      pt1 = points[i + 1] || points.first
      normal.x += (pt0.y - pt1.y) * (pt0.z + pt1.z)
      normal.y += (pt0.z - pt1.z) * (pt0.x + pt1.x)
      normal.z += (pt0.x - pt1.x) * (pt0.y + pt1.y)
    end

    normal.normalize
  end
  private_class_method :polygon_normal
end
