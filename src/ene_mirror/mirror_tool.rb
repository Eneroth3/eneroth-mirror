# frozen_string_literal: true

module Eneroth
  module Mirror
    Sketchup.require "#{PLUGIN_ROOT}/vendor/refined_input_point"
    Sketchup.require "#{PLUGIN_ROOT}/bounds_helper"
    Sketchup.require "#{PLUGIN_ROOT}/entity_helper"
    Sketchup.require "#{PLUGIN_ROOT}/tool"
    Sketchup.require "#{PLUGIN_ROOT}/extract_lines"
    Sketchup.require "#{PLUGIN_ROOT}/copy_entities"
    Sketchup.require "#{PLUGIN_ROOT}/geom_helper"

    using RefinedInputPoint

    # Tool for mirroring selection around a plane.
    class MirrorTool < Tool
      # Side of plane preview in logical pixels.
      PREVIEW_SIDE = 100

      # Side of flip handle in logical pixels.
      FLIP_SIDE = 30

      # Spacing from bounds to flip handle in logical pixels.
      FLIP_SPACING = 10

      FLIP_COLOR = Sketchup::Color.new(0, 255, 0)
      FLIP_HOVER_COLOR = Sketchup::Color.new(255, 0, 0)
      FLIP_EDGE_COLOR = Sketchup::Color.new(0, 0, 0)

      # Native Move
      CURSOR_MOVE = 641

      # Native Move Copy
      CURSOR_COPY = 642

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def initialize
        @ip = Sketchup::InputPoint.new
        @ip_direction = Sketchup::InputPoint.new
        @bounds_intersection = nil
        @normal = nil

        @copy_mode = false
        @mouse_down = false

        # Corners for the X, Y and Z flip handles
        @handle_corners = []
        # Planes for the X, Y and Z flip handles
        @handle_planes = []
        # Currently hovered handle. 0 for X, 1 for Y, 2 for Z, nil for none.
        @hovered_handle = nil
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def activate
        super

        model = Sketchup.active_model

        @pre_selection = !model.selection.empty?

        set_up_handles(model.active_view) if @pre_selection

        # Flat array of points making up lines to preview, without any
        # mirroring.
        @preview_lines = ExtractLines.extract_lines(model.selection)

        onSetCursor
        update_status_text
        model.active_view.invalidate
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
        # Move preview
        if plane? && !view.model.selection.empty?
          tr = transformation
          view.draw(GL_LINES, @preview_lines.map { |pt| pt.transform(tr) })
        end

        # Drag direction line
        if @mouse_down && !@hovered_handle
          view.set_color_from_line(@ip.position, @ip_direction.position)
          view.line_stipple = "-"
          view.draw(GL_LINES, @ip.position, @ip_direction.position)
          view.line_stipple = ""
        end

        # Flip handles
        if @pre_selection
          @handle_corners.each_with_index do |points, index|
            view.drawing_color = @hovered_handle == index ? FLIP_HOVER_COLOR : FLIP_COLOR
            view.draw(GL_POLYGON, points)
            # TODO: Draw stroke slightly in front to stop Z-fighting
            view.drawing_color = FLIP_EDGE_COLOR
            view.draw(GL_LINE_LOOP, points)
            # TODO: Draw a transparent version in 2D screen space, to get an
            # X-ray-like style when behind geometry.
            # Draw the active handle only in 2D screen space to show it on top
            # of any geometry, like in Scale tool.
          end
        end

        # Custom mirror plane
        draw_mirror_plane(view, @ip.position, @normal) if plane? && !@hovered_handle

        @ip.draw(view)
        @ip_direction.draw(view) if @mouse_down && !@hovered_handle

        view.tooltip = tooltip
      end

      # TODO: Instructor
      # TODO: Fix undo previewing wrong content.

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
      def onKeyDown(key, _repeat, _flags, _view)
        @copy_mode = !@copy_mode if key == COPY_MODIFIER_KEY
        onSetCursor

        # Don't stop propagation.
        false
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonDown(_flags, _x, _y, _view)
        @mouse_down = true
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onLButtonUp(_flags, _x, _y, view)
        @mouse_down = false
        transform
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onSetCursor
        UI.set_cursor(@copy_mode ? CURSOR_COPY : CURSOR_MOVE)
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def onMouseMove(flags, x, y, view)
        # If selection has been emptied, e.g. from undo or the erase command,
        # revert to pick phase.
        @pre_selection = false if view.model.selection.empty?

        # When shift is pressed we don't pick the plane normal,
        # only its position. Lock direction similarly to Section Plane tool.
        normal_lock = flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK

        if @mouse_down
          # Press and drag to pick a custom mirror plane from any two points.
          # Similar to Rotate tool.
          pick_direction(view, x, y)
        else
          @ip.pick(view, x, y)
          pick_bounds(view, x, y)
          pick_plane(view, x, y, normal_lock)
          pick_selection(view.model) unless @pre_selection
        end

        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def resume(view)
        set_up_handles(view) if @pre_selection
        view.invalidate
        update_status_text
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def suspend(view)
        view.invalidate
      end

      # @api
      # @see https://extensions.sketchup.com/en/content/eneroth-tool-memory
      def ene_tool_cycler_name
        OB["action_mirror"]
      end

      # @api
      # @see https://extensions.sketchup.com/en/content/eneroth-tool-memory
      def ene_tool_cycler_icon
        File.join(PLUGIN_ROOT, "images", "mirror.svg")
      end

      private

      def update_status_text
        Sketchup.status_text = OB[:status_text]
      end

      # Used to pick an entity to mirror when not using pre-selection.
      def pick_selection(model)
        model.selection.clear
        hovered = (@ip.instance_path.to_a & model.active_entities.to_a).first
        return unless hovered

        model.selection.add(hovered)
        @preview_lines = ExtractLines.extract_lines(model.selection)
      end

      # Used to list where the mouse pickray intersect the bounds of a
      # selected group or component.
      # REVIEW: I can't remember why this is a separate thing and not in 
      # pick_plane.
      def pick_bounds(view, x, y)
        ray = view.pickray(x, y)
        intersections = view.model.selection.map do |instance|
          next unless EntityHelper.instance?(instance)

          # REVIEW: Move my selection bounds thingy to BoundsHelper?
          BoundsHelper.intersect_line(ray, instance.definition.bounds,
                                      instance.transformation)
        end
        @bounds_intersection = intersections.compact.min_by(&:distance)
      end

      # TODO: Call on redo/undo

      # Set up the flip handles around the model selection.
      def set_up_handles(view)
        @handle_corners = []
        @handle_planes = []

        bounds = BoundsHelper.selection_bounds(view.model.selection)
        bounds_tr = BoundsHelper.selection_bounds_transformation(view.model.selection)
        bounds_center = bounds.center.transform(bounds_tr)
        # From face of bounds to center of each handle
        spacing = view.pixels_to_model(FLIP_SPACING + FLIP_SIDE / 2, bounds_center)

        cam_direction = view.camera.direction

        # REVIEW: Set up dynamically in a loop.
        # Use helper methods to get bounds side length and transformation axis by index.

        # Z side handle
        # Flip Along X
        handle_normal = bounds_tr.xaxis
        # bounds.depth = the bounds height
        handle_offset = bounds_tr.zaxis.tap { |v| v.length = bounds.depth / 2 + spacing }
        handle_offset.reverse! if handle_offset % cam_direction > 0
        handle_center = bounds_center.offset(handle_offset)
        @handle_corners << calculate_plane_corners(view, handle_center, handle_normal, FLIP_SIDE)
        @handle_planes << [handle_center, handle_normal]

        # X side handle
        # Flip Along Y
        handle_normal = bounds_tr.yaxis
        handle_offset = bounds_tr.xaxis.tap { |v| v.length = bounds.width / 2 + spacing }
        handle_offset.reverse! if handle_offset % cam_direction > 0
        handle_center = bounds_center.offset(handle_offset)
        @handle_corners << calculate_plane_corners(view, handle_center, handle_normal, FLIP_SIDE)
        @handle_planes << [handle_center, handle_normal]

        # Y side handle
        # Flip Along Z
        handle_normal = bounds_tr.zaxis
        # bounds.height = the bounds depth
        handle_offset = bounds_tr.yaxis.tap { |v| v.length = bounds.height / 2 + spacing }
        handle_offset.reverse! if handle_offset % cam_direction > 0
        handle_center = bounds_center.offset(handle_offset)
        @handle_corners << calculate_plane_corners(view, handle_center, handle_normal, FLIP_SIDE)
        @handle_planes << [handle_center, handle_normal]
      end

      # Used to pick mirror plane from hovered entity on mouse move.
      def pick_plane(view, x, y, normal_lock)
        # Flip plane "handles" have precedence over all else.

        @hovered_handle = nil
        # When Shift is pressed down and the direction is locked, it doesn't
        # make much sense to pick the handles. The user has chosen the plane
        # direction already, and wants a plane position from the geometry.
        unless normal_lock
          @handle_corners.each_with_index do |corners, index|
            screen_points = corners.map { |pt| view.screen_coords(pt) }
            next unless Geom.point_in_polygon_2D([x, y, 0], screen_points, true)

            @hovered_handle = index
            @normal = @handle_planes[index][1]
            @ip = Sketchup::InputPoint.new(@handle_planes[index][0])
            axis_name = ["red", "green", "blue"][index]
            # TODO: Distinguish "Component's Red" from model "Red".
            @tooltip_override = OB["flip_along_#{axis_name}"]

            return
          end
        end

        # InputPoint in selection has precedence.
        # Then InputPoint or point on bounds are used depending on which is
        # closest to the camera.
        if ip_in_selection? || !bounds_in_front_of_ip?
          # From InputPoint.
          @normal = ip_direction unless normal_lock
          @tooltip_override = nil
        else
          # From Bounds.
          @ip = Sketchup::InputPoint.new(@bounds_intersection.position)
          @normal = @bounds_intersection.normal unless normal_lock
          @tooltip_override = OB[:inference_on_bounds]
        end
      end

      def ip_direction
        # Typically flip direction is taken from a hovered face.
        # If an edge, outside of the selection, is hovered, its direction can
        # also be used. If the edge is inside of the selection, you likely don't
        # want to flip along it, as it would create an overlap.
        if @ip.source_edge && !ip_in_selection?
          @ip.source_edge.line[1].transform(@ip.transformation)
        elsif @ip.source_face
          GeomHelper.transform_as_normal(@ip.source_face.normal, @ip.transformation)
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

      # Used to pick custom direction when holding down mouse.
      def pick_direction(view, x, y)
        # If the user presses down the mouse on a handle, we don't want to pick a custom direction.
        return if @hovered_handle

        @ip_direction.pick(view, x, y, @ip)
        direction = @ip_direction.position - @ip.position
        @normal = direction if direction.valid?
      end

      def plane?
        !!@normal
      end

      # Calculate transformation from current position and normal.
      def transformation
        plane = Geom::Transformation.new(@ip.position, @normal)
        plane * Geom::Transformation.scaling(1, 1, -1) * plane.inverse
      end

      # Carry out the transformation on the selected entities.
      def transform
        model = Sketchup.active_model

        return if !plane? || model.selection.empty?

        model.start_operation(OB[:action_mirror], true)
        added = CopyEntities.move(transformation, model.selection, @copy_mode)
        added.reject!(&:deleted?)
        model.selection.add(added)
        model.commit_operation

        @preview_lines = ExtractLines.extract_lines(model.selection)
        @normal = nil
        @bounds_intersection = nil
        set_up_handles(model.active_view)
      end

      # Get corners of a square used to convey a plane to the user.
      def calculate_plane_corners(view, position, normal, side)
        points = [
          Geom::Point3d.new(-side / 2, -side / 2, 0),
          Geom::Point3d.new(side / 2, -side / 2, 0),
          Geom::Point3d.new(side / 2, side / 2, 0),
          Geom::Point3d.new(-side / 2, side / 2, 0)
        ]
        transformation =
          Geom::Transformation.new(position, normal) *
          Geom::Transformation.scaling(view.pixels_to_model(1, position))
        points.each { |pt| pt.transform!(transformation) }

        points
      end

      # Draw the mirror plane.
      def draw_mirror_plane(view, position, normal)
        view.set_color_from_line(ORIGIN, ORIGIN.offset(normal))
        points = calculate_plane_corners(view, position, normal, PREVIEW_SIDE)
        view.draw(GL_LINE_LOOP, points)
      end

      # Get the current tool tooltip.
      def tooltip
        return @ip_direction.tooltip if @mouse_down

        @tooltip_override || @ip.tooltip
      end
    end
  end
end
