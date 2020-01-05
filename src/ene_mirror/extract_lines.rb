# frozen_string_literal: true

module Eneroth
  module Mirror
    # Extract line information from entities to later use to draw a preview.
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
    end
  end
end
