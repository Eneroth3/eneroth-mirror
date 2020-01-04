# frozen_string_literal: true

module Eneroth
  module Mirror
    # Geometric functionality.
    module MyGeom
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

      # Return new vector transformed as a normal.
      #
      # Transforming a normal vector as a ordinary vector can give it a faulty
      # direction if the transformation is non-uniformly scaled or sheared. This
      # method assures the vector stays perpendicular to its perpendicular plane
      # when a transformation is applied.
      #
      # @param normal [Geom::Vector3d]
      # @param transformation [Geom::Transformation]
      #
      # @return [Geom::Vector3d]
      def self.transform_as_normal(normal, transformation)
        tangent = normal.axes[0].transform(transformation)
        bi_tangent = normal.axes[1].transform(transformation)

        (tangent * bi_tangent).normalize
      end
    end
  end
end
