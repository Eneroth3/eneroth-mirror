# frozen_string_literal: true

module Eneroth
  module Mirror
    # Generic tool functionality, like activation and menu command state.
    #
    # Designed to be reusable between tools and extensions.
    #
    # When inhering from this, call `super` in `activate` and `deactivate`.
    class Tool
      # Whether this is the active tool in SketchUp.
      @active = false

      # Activate a tool of this class.
      # Intended to be called on subclasses.
      #
      # @return [Object] The Ruby tool object.
      def self.activate(*args, &block)
        tool = block ? new(*args, &block) : new(*args)
        Sketchup.active_model.select_tool(tool)

        tool
      end

      # Check if a tool of this class is active.
      # Intended to be called on subclasses.
      def self.active?
        @active
      end

      # Get command state to use in toggle tool activation command.
      # Intended to be called on subclasses.
      #
      # @return [MF_CHECKED, MF_UNCHECKED]
      def self.command_state
        active? ? MF_CHECKED : MF_UNCHECKED
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def activate
        self.class.instance_variable_set(:@active, true)
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def deactivate(*_args)
        self.class.instance_variable_set(:@active, false)
      end
    end
  end
end
