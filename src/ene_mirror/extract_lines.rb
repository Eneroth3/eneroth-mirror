# frozen_string_literal: true

module Eneroth
  module Mirror
    # Extract line information from entities to later use to draw a preview.
    # REVIEW: Rename module.
    module ExtractLines
      # Extract line information from entities to later use to draw a preview.
      #
      # @param entities [Array<Sketchup::DrawingElement>]
      # @param transformation [Geom::Transformation]
      #
      # @return [Array<Geom::Point3d>]
      def self.extract_lines(entities, transformation = IDENTITY)
        entities =
          entities.to_a + entities.grep(Sketchup::Face).flat_map(&:edges).uniq
        entities.flat_map do |entity|
          case entity
          when Sketchup::Edge
            entity.vertices.map { |v| v.position.transform(transformation) }
          when Sketchup::ComponentInstance, Sketchup::Group
            extract_lines(
              entity.definition.entities,
              transformation * entity.transformation
            )
          end
        end.compact
      end
      
      TriangleData = Struct.new(:corners, :normals, :material)
      
      # REVIEW: Make private?
      def self.triangle_data(face, transformation)
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
      
      # Extract triangle information from entities to later use to draw a preview.
      #
      # @param entities [Array<Sketchup::DrawingElement>]
      # @param transformation [Geom::Transformation]
      #
      # @return [Array<TriangleData>]
      def self.extract_triangles(entities, transformation = IDENTITY)
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
    end
  end
end
