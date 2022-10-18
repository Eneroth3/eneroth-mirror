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
        @triangle_data = ExtractLines.extract_triangles(entities)
      end

      # Draw the PreviewGeometry. Typically called in each SketchUp tool draw
      # call.
      #
      # @param view [Sketchup::View]
      # @param transformation [Geom::Transformation]
      #   Typically calculated from mouse movement.
      def draw(view, transformation)
        tr = transformation
        corners = @triangle_data.map { |td| td.corners.map { |c| c.transform(tr) }}.flatten
        normals = @triangle_data.map { |td| td.normals.map { |n| n.transform(tr) }}.flatten
        view.drawing_color = [255, 255, 255, @transparency] # TODO: Get from face.
        view.draw(GL_TRIANGLES, corners, normals: normals)
      end

      private

      def extract_triangles(entities, transformation = IDENTITY)
        # TODO: Resolve material from parent
        # (Can look at Eneroth Difference Report for this)
        entities =
          entities.to_a + entities.grep(Sketchup::Face).flat_map(&:edges).uniq
        entities.flat_map do |entity|
          case entity
          when Sketchup::Face
            triangle_data(entity, transformation)
          when Sketchup::ComponentInstance, Sketchup::Group
            extract_triangles(
              entity.definition.entities,
              transformation * entity.transformation
            )
          end
        end.compact.flatten
      end

      TriangleData = Struct.new(:corners, :normals, :material)

      def triangle_data(face, transformation)
        # 4 = Include normals
        mesh = face.mesh(4)
        mesh.polygons.map do |triangle|
          corners = []
          normals = []
          triangle.each do |i|
            corners << mesh.point_at(i.abs).transform(transformation)
            # TODO: Transform as normal to honor any shearing
            normals << mesh.normal_at(i.abs).transform(transformation)
          end
          TriangleData.new(corners, normals, face.material)
        end
      end
    end
  end
end
