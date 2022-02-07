# frozen_string_literal: true

module Eneroth
  module Mirror
    module EntityHelper
      # Check if an entity is an instance (a group or component instance).
      #
      # @param entity [Sketchup::Entity]
      #
      # @return [Boolean]
      def self.instance?(entity)
        [Sketchup::Group, Sketchup::ComponentInstance].include?(entity.class)
      end
    end
  end
end
