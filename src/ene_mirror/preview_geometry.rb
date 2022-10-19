# frozen_string_literal: true

module Eneroth
  module Mirror
    # Holds a copy of some model geometry that can later be used to draw a
    # preview to the view using a custom transformation, e.g. to display what
    # the result would be of a move or copy operation.
    #
    # The data is simplified and doesn't retain the component hierarchy, only
    # the flat geometry.
    class PreviewGeometry
      # Create a new PreviewGeometry. Typically called when a tool is activated
      # or reset.
      #
      # @param entities
      #   [Array<Sketchup::Drawingelement>, Sketchup::Entities, Sketchup::Selection]
      # @param transformation
      #   [Geom::Transformation]
      def initialize(entities, transparency: 0.5, transformation: IDENTITY)
        # REVIEW: Transparency vs opacity
        @transparency = transparency
        @face_data = recurse_entities(entities)
      end

      # Draw the PreviewGeometry. Typically called in each SketchUp tool draw
      # call.
      #
      # @param view [Sketchup::View]
      # @param transformation [Geom::Transformation]
      #   Typically calculated from mouse movement.
      def draw(view, transformation)
        @face_data.each do |face_data|
          color =
            if face_data.material
              Sketchup::Color.new(face_data.material.color)
            else
              view.model.rendering_options["FaceFrontColor"]
            end
          color.alpha = @transparency
          view.drawing_color = color

          corners = face_data.triangle_corners.map { |c| c.transform(transformation) }
          normals = face_data.triangle_normals.map { |n| transform_as_normal(n, transformation) }

          view.draw(GL_TRIANGLES, corners, normals: normals)
        end
      end

      private

      def recurse_entities(entities, transformation = IDENTITY, parent_material = nil)
        entities =
          entities.to_a + entities.grep(Sketchup::Face).flat_map(&:edges).uniq
        entities.flat_map do |entity|
          case entity
          when Sketchup::Face
            extract_face_data(entity, transformation, parent_material)
          when Sketchup::ComponentInstance, Sketchup::Group
            recurse_entities(
              entity.definition.entities,
              transformation * entity.transformation,
              entity.material || parent_material
            )
          end
        end.compact.flatten
      end

      # REVIEW: Consider storing UVQ. Render material in #draw.
      FaceData = Struct.new(:triangle_corners, :triangle_normals, :material)

      def extract_face_data(face, transformation, parent_material)
        # 4 = Include normals
        mesh = face.mesh(4)
        triangle_corners = []
        triangle_normals = []
        mesh.polygons.map do |triangle|
          triangle.each do |i|
            triangle_corners << mesh.point_at(i.abs).transform(transformation)
            triangle_normals << transform_as_normal(mesh.normal_at(i.abs), transformation)
          end
        end

        FaceData.new(triangle_corners, triangle_normals, face.material || parent_material)
      end

      # Transform a normal vector.
      #
      # Using a conventional vector transformation on a normal vector can stop
      # it from being perpendicular to a plane, if the transformation includes
      # non-uniform scaling or shearing. This method retains the relation to a
      # perpendicular plane.
      #
      # @param normal [Geom::Vector3d]
      # @param transformation [Geom::Transformation]
      #
      # @return [Vector3d]
      def transform_as_normal(normal, transformation)
        a = transformation.to_a
        transposed = Geom::Transformation.new([
          a[0], a[4], a[8],  0,
          a[1], a[5], a[9],  0,
          a[2], a[6], a[10], 0,
          0,    0,    0,     a[15]
        ])

        normal.transform(transposed).normalize
      end
    end
  end
end
