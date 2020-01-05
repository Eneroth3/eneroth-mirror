# frozen_string_literal: true

module Eneroth
  module Mirror
    Sketchup.require "#{PLUGIN_ROOT}/vendor/refined_input_point"
    Sketchup.require "#{PLUGIN_ROOT}/bounds_helper"
    Sketchup.require "#{PLUGIN_ROOT}/tool"
    Sketchup.require "#{PLUGIN_ROOT}/extract_lines"
    Sketchup.require "#{PLUGIN_ROOT}/copy_entities"
    Sketchup.require "#{PLUGIN_ROOT}/my_geom"

    using RefinedInputPoint

    # Tool for mirroring selection around a plane.
    class MirrorTool < Tool
      # Radius of plane preview in logical pixels.
      CIRCLE_RADIUS = 50

      # Segment count for plane preview.
      CIRCLE_SEGMENTS = 48

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def initialize
        model = Sketchup.active_model

        @ip = Sketchup::InputPoint.new
        @ip_direction = Sketchup::InputPoint.new
        @bounds_intersection = nil
        @normal = nil

        # Flat array of points making up lines to preview, without any
        # mirroring.
        @preview_lines = ExtractLines.extract_lines(model.selection)

        @copy_mode = true
        @mouse_down = false
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def deactivate(view)
        super

        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def draw(view)
        if plane? && !view.model.selection.empty?
          tr = transformation
          view.draw(GL_LINES, @preview_lines.map { |pt| pt.transform(tr) })
        end
        if @mouse_down
          view.line_stipple = "-"
          view.draw(GL_LINES, @ip.position, @ip_direction.position)
          view.line_stipple = ""
        end

        preview_circle(view, @ip.position, @normal) if plane?
        @ip.draw(view)
        @ip_direction.draw(view) if @mouse_down

        view.tooltip =
          if @mouse_down
            @ip_direction.tooltip
          else
            @tooltip_override || @ip.tooltip
          end
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def getExtents
        bounds = Sketchup.active_model.bounds
        bounds.add(@ip.position) if @ip.position
        bounds.add(@ip_direction.position) if @ip_direction.position

        bounds
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonDown(_flags, x, y, view)
        @mouse_down = true
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonUp(_flags, _x, _y, view)
        @mouse_down = false
        return if !plane? || view.model.selection.empty?

        model = Sketchup.active_model
        model.start_operation(OB[:action_mirror], true)
        added = CopyEntities.move(transformation, model.selection, @copy_mode)
        model.selection.add(added)
        model.commit_operation

        @preview_lines = ExtractLines.extract_lines(model.selection)
        @normal = nil
        @bounds_intersection = nil
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onMouseMove(_flags, x, y, view)
        if @mouse_down
          @ip_direction.pick(view, x, y, @ip)
          return if @ip_direction.position == @ip.position

          @normal = @ip_direction.position - @ip.position
        else
          @ip.pick(view, x, y)
          pick_bounds(view, x, y)
          pick_plane
        end

        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def resume(view)
        view.invalidate
        ### update_status_text # TODO: Set status text here and on activate.
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def suspend(view)
        view.invalidate
      end

      private

      def pick_bounds(view, x, y)
        ray = view.pickray(x, y)
        intersections = view.model.selection.map do |instance|
          next unless instance?(instance)

          BoundsHelper.intersect_line(ray, instance.definition.bounds,
                                      instance.transformation)
        end
        @bounds_intersection = intersections.compact.min_by(&:distance)
      end

      def pick_plane
        # InputPoint in selection has precedence.
        # Then InputPoint or point on bounds are used depending on which is
        # closest.
        if ip_in_selection? || !bounds_in_front_of_ip?
          # From InputPoint.
          @normal = ip_direction
          @tooltip_override = nil
        else
          # From Bounds.
          @ip = Sketchup::InputPoint.new(@bounds_intersection.position)
          @normal = @bounds_intersection.normal
          @tooltip_override = OB[:inference_on_bounds]
        end
      end

      def ip_direction
        # Flip along hovered edge, but not if edge is in the selection.
        # User likely doesn't want to flip object around itself causing an
        # overlap.
        if @ip.source_edge && !ip_in_selection?
          @ip.source_edge.line[1].transform(@ip.transformation)
        elsif @ip.source_face
          MyGeom.transform_as_normal(@ip.source_face.normal, @ip.transformation)
        end
      end

      def ip_in_selection?
        !(@ip.instance_path.to_a & Sketchup.active_model.selection.to_a).empty?
      end

      def bounds_in_front_of_ip?
        return false unless @bounds_intersection

        eye = Sketchup.active_model.active_view.camera.eye

        @bounds_intersection.position.distance(eye) < @ip.position.distance(eye)
      end

      def plane?
        !!@normal
      end

      def transformation
        plane = Geom::Transformation.new(@ip.position, @normal)
        plane * Geom::Transformation.scaling(1, 1, -1) * plane.inverse
      end

      def instance?(entity)
        [Sketchup::Group, Sketchup::ComponentInstance].include?(entity.class)
      end

      def preview_circle(view, position, direction, radius = CIRCLE_RADIUS)
        points = CIRCLE_SEGMENTS.times.map do |n|
          a = 2 * Math::PI / CIRCLE_SEGMENTS * n

          Geom::Point3d.new(Math.cos(a) * radius, Math.sin(a) * radius, 0)
        end
        transformation =
          Geom::Transformation.new(position, direction) *
          Geom::Transformation.scaling(view.pixels_to_model(1, position))
        points.each { |pt| pt.transform!(transformation) }

        view.set_color_from_line(ORIGIN, ORIGIN.offset(direction))
        view.draw(GL_LINE_LOOP, points)
      end
    end
  end
end
