# frozen_string_literal: true

module Eneroth
  module Mirror
    # Copy entities within drawing context.
    module CopyEntities
      # Move entities within drawing context.
      #
      # @param transformation [Geom::transformation]
      # @param entities [Array<Sketchup::Drawingelement>, Sketchup::Selection]
      # @param copy_mode [Boolean]
      #
      # @return [Array<Sketchup::DrawingElements>] moved entities.
      def self.move(transformation, entities, copy_mode = false)
        return copy(transformation, entities) if copy_mode

        context = entities.first.parent.entities

        context.transform_entities(transformation, entities)

        entities.to_a
      end

      # Copy entities within drawing context.
      #
      # @param transformation [Geom::transformation]
      # @param entities [Array<Sketchup::Drawingelement>, Sketchup::Selection]
      #
      # @return [Array<Sketchup::DrawingElements>] copied entities.
      def self.copy(transformation, entities)
        context = entities.first.parent.entities

        # HACK: Use temporary group for copying, rather than replicate all
        # entities from scratch with correct properties such as UV mapping.
        # Ideally Sketchup::Entities should have a copy_entities method with the
        # same signature as move_entities.
        # https://github.com/SketchUp/api-issue-tracker/issues/41

        temp_group = context.add_group(entities)

        new_entities = context.add_instance(
          temp_group.definition,
          transformation * temp_group.transformation
        ).explode

        temp_group.explode

        new_entities.grep(Sketchup::Drawingelement)
      end
    end
  end
end
