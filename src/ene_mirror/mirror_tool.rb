# frozen_string_literal: true

module Eneroth
  module Mirror
    ### Sketchup.require "#{PLUGIN_ROOT}/mirror"
    Sketchup.require "#{PLUGIN_ROOT}/bounds_helper"
    Sketchup.require "#{PLUGIN_ROOT}/tool"
    Sketchup.require "#{PLUGIN_ROOT}/my_geom"

    # Tool for mirroring selection around a plane.
    class MirrorTool < Tool
      CIRCLE_RADIUS = 50
      CIRCLE_SEGMENTS = 48

      def initialize
        @ip = Sketchup::InputPoint.new
        @bounds_intersection = nil

        @point = nil
        @normal = nil
        @tooltip = nil
      end

      def deactivate(view)
        super

        view.invalidate
      end

      def draw(view)
        preview_circle(view, @point, @normal) if @normal

        @ip.draw(view)
        view.tooltip = @tooltip if @tooltip
      end

      def getExtents
        bounds = Sketchup.active_model.bounds
        bounds.add(@point) if @point

        bounds
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @point
        view.model.active_entities.add_cpoint(@point)
      end

      def onMouseMove(_flags, x, y, view)
        @ip.pick(view, x, y)
        pick_bounds(view, x, y)
        pick_plane

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
          @normal = ip_direction
          @point = @ip.position
          @tooltip = @ip.tooltip
        else
          @point = @bounds_intersection.position
          @normal = @bounds_intersection.normal
          @tooltip = OB[:inference_on_bounds]
        end
      end

      def ip_direction
        # TODO: Make sure face is what @ip gets position from and not just in
        # the background.

        # Flip along hovered edge, but not if edge is in the selection.
        # User likely doesn't want to flip object around itself causing an
        # overlap.
        if @ip.edge && !ip_in_selection?
          @ip.edge.line[1].transform(@ip.transformation)
        elsif @ip.face
          # TODO: Transform as normal.
          @ip.face.normal.transform(@ip.transformation)
        end
      end

      def ip_in_selection?
        !(@ip.instance_path.to_a & Sketchup.active_model.selection.to_a).empty?
      end

      def bounds_in_front_of_ip?
        @bounds_intersection && @bounds_intersection.distance < ip_distance
      end

      def ip_distance
        # TODO: Make work properly in parallel projection.
        @ip.position.distance(Sketchup.active_model.active_view.camera.eye)
      end

      def instance?(entity)
        [Sketchup::Group, Sketchup::ComponentInstance].include?(entity.class)
      end

      def preview_circle(view, position, direction)
        points = CIRCLE_SEGMENTS.times.map { |n|
          a = 2*Math::PI/CIRCLE_SEGMENTS*n
          Geom::Point3d.new(Math.cos(a)*CIRCLE_RADIUS, Math.sin(a)*CIRCLE_RADIUS, 0)
        }
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
