# frozen_string_literal: true

module Eneroth
  module Mirror
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"
    Sketchup.require "#{PLUGIN_ROOT}/entity_helper"

    # Extract useful info from bounding boxes.
    #
    # Note that the bounds of an instance itself are invisible in SketchUp.
    # Typically what you want is the transformed bounds of its definition.
    #
    # @examples
    #   # Corners of the invisible bounds orthogonal to the drawing axes.
    #   BoundsHelper.corners(instance.bounds)
    #
    #   # Corners of visible selection bounds for an instance.
    #   BoundsHelper.corners(
    #     instance.definition.bounds,
    #     instance.transformation
    #   )
    module BoundsHelper
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
      # bottom front left, bottom front right, bottom back left, bottom back
      # right, top front left, top front right, top back left, top back right.
      #
      # @param bounds [Geom::BoundingBox]
      # @param transformation [Geom::Transformation]
      #
      # @return [Array<Geom::Point3d>]
      def self.corners(bounds, transformation = IDENTITY)
        Array.new(8) { |n| bounds.corner(n).transform(transformation) }
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
      # @param transformation [Geom::Transformation]
      #
      # @return [Array<Geom::Vector3d>]
      def self.normals(transformation = IDENTITY)
        [
          GeomHelper.transform_as_normal(X_AXIS, transformation),
          GeomHelper.transform_as_normal(Y_AXIS, transformation),
          GeomHelper.transform_as_normal(Z_AXIS, transformation),
          GeomHelper.transform_as_normal(X_AXIS.reverse, transformation),
          GeomHelper.transform_as_normal(Y_AXIS.reverse, transformation),
          GeomHelper.transform_as_normal(Z_AXIS.reverse, transformation)
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
        normals = normals(transformation)

        [
          [corners[7], normals[0]],
          [corners[7], normals[1]],
          [corners[7], normals[2]],
          [corners[0], normals[3]],
          [corners[0], normals[4]],
          [corners[0], normals[5]]
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
        line_space = Geom::Transformation.new(*line)
        bounds_line_space = line_space.inverse * transformation
        flipped = GeomHelper.flipped?(bounds_line_space)
        sides = sides(bounds, bounds_line_space)
        index = sides.find_index { |s| within?(s, flipped) }
        return unless index

        plane = planes(bounds, transformation)[index]
        intersection = Geom.intersect_line_plane(line, plane)

        Intersection.new(
          intersection,
          plane[1],
          intersection.transform(line_space.inverse).z,
          index
        )
      end

      # Get the bounding box for the selection.
      #
      # This may be in global coordinates, or if only a single instance is
      # selected, in its internal coordinates.
      #
      # @param selection [Sketchup::Selection]
      #
      # @return [Geom::BoundingBox]
      #
      # @see selection_bounds_transform
      def self.selection_bounds(selection)
        if selection.size == 1 && EntityHelper.instance?(selection.first)
          return selection.first.definition.bounds
        end

        bounds = Geom::BoundingBox.new
        selection.each { |e| bounds.add(e.bounds) }

        bounds
      end

      # Get the bounding box transformation for the selection.
      #
      # @param selection [Sketchup::Selection]
      #
      # @return [Geom::BoundingBox]
      #
      # @see selection_bounds_transform
      def self.selection_bounds_transformation(selection)
        if selection.size == 1 && EntityHelper.instance?(selection.first)
          return selection.first.transformation
        end

        IDENTITY
      end

      # Private

      def self.within?(corners, flipped)
        return false if facing?(corners) == flipped

        Geom.point_in_polygon_2D(ORIGIN, corners, true)
      end
      private_class_method :within?

      def self.facing?(corners)
        GeomHelper.polygon_normal(corners).z.negative?
      end
      private_class_method :facing?
    end
  end
end
