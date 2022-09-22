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

      FLIP_COLOR = Sketchup::Color.new(255, 255, 255, 0.5)
      FLIP_HOVER_COLOR = Sketchup::Color.new(0, 255, 0, 0.5)
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
        @normal = nil

        @copy_mode = false
        @mouse_down = false

        # Corners for the standard X, Y, Z flipping planes
        @standard_plane_corners = []
        # Planes for the standard X, Y and Z flip planes
        @standard_plane_planes = []
        # Currently hovered standard plane. 0 for X, 1 for Y, 2 for Z, nil for none.
        @hovered_standard_plane = nil
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def activate
        super

        model = Sketchup.active_model

        @pre_selection = !model.selection.empty?

        init_standard_planes(model.active_view) if @pre_selection
        init_preview_source(model)

        model.add_observer(self)

        onSetCursor
        update_status_text
        model.active_view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def deactivate(view)
        super

        view.model.remove_observer(self)

        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def draw(view)
        # Mirror preview
        if plane? && !view.model.selection.empty?
          tr = transformation
          view.draw(GL_LINES, @preview_lines.map { |pt| pt.transform(tr) })
        end

        # Drag direction line
        if @mouse_down && !@hovered_standard_plane
          view.set_color_from_line(@ip.position, @ip_direction.position)
          view.line_stipple = "-"
          view.draw(GL_LINES, @ip.position, @ip_direction.position)
          view.line_stipple = ""
        end

        # Standard mirror planes
        draw_standard_planes(view) if @pre_selection

        # Custom mirror plane
        draw_custom_mirror_plane(view, @ip.position, @normal) if plane? && !@hovered_standard_plane

        @ip.draw(view)
        @ip_direction.draw(view) if @mouse_down && !@hovered_standard_plane

        view.tooltip = @tooltip_text
      end

      # TODO: Instructor

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
          # Pick from what is currently hovered.
          @ip.pick(view, x, y)
          pick_plane(view, x, y, normal_lock)
          pick_selection(view.model) unless @pre_selection
        end

        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def resume(view)
        init_standard_planes(view) if @pre_selection
        view.invalidate
        update_status_text
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/Tool.html
      def suspend(view)
        view.invalidate
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def onTransactionRedo(model)
        init_standard_planes(model.active_view)
        init_preview_source(model)
      end

      # @api
      # @see https://ruby.sketchup.com/Sketchup/ModelObserver.html
      def onTransactionUndo(model)
        init_standard_planes(model.active_view)
        init_preview_source(model)
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
        init_preview_source(model)
      end

      # Set up the standard mirror planes around the model selection.
      def init_standard_planes(view)
        @standard_plane_corners = []
        @standard_plane_planes = []

        bounds = BoundsHelper.selection_bounds(view.model.selection)
        bounds_tr = BoundsHelper.selection_bounds_transformation(view.model.selection)
        bounds_center = bounds.center.transform(bounds_tr)
        bounds_corners = 8.times.map { |i| bounds.corner(i) }

        # Visually scale up planes slightly so they don't tangent the bounding box.
        tr_size = Geom::Transformation.scaling(bounds.center.transform(bounds_tr), 1.2)

        # Flip along X
        normal = bounds_tr.xaxis
        corners = bounds_corners.values_at(0, 2, 6, 4)
        corners.map! { |c| c.transform(bounds_tr) }
        corners.map! { |c| c.offset(normal, bounds.width / 2) }
        corners.map! { |c| c.transform(tr_size) }
        @standard_plane_corners << corners
        @standard_plane_planes << [bounds_center, normal]

        # Flip along Y
        normal = bounds_tr.yaxis
        corners = bounds_corners.values_at(0, 1, 5, 4)
        corners.map! { |c| c.transform(bounds_tr) }
        corners.map! { |c| c.offset(normal, bounds.height / 2) }
        corners.map! { |c| c.transform(tr_size) }
        @standard_plane_corners << corners
        @standard_plane_planes << [bounds_center, normal]

        # Flip along Z
        normal = bounds_tr.zaxis
        corners = bounds_corners.values_at(0, 1, 3, 2)
        corners.map! { |c| c.transform(bounds_tr) }
        corners.map! { |c| c.offset(normal, bounds.depth / 2) }
        corners.map! { |c| c.transform(tr_size) }
        @standard_plane_corners << corners
        @standard_plane_planes << [bounds_center, normal]
      end

      # A plane the user may be choosing as mirror plane.
      # - plane [Array<Geom::Point3d, Geom::Vector3d>]
      # - depth [Length]
      #     Used to prioritize what is being picked.
      # - type [:bounds, :standard_plane, :geometry]
      #     Used to prioritize what is being picked.
      # - standard_plane_index [nil, Integer]
      #     Used to highlight the hovered standard plane.
      # - tooltip [String]
      PossiblePick = Struct.new(:plane, :depth, :type, :standard_plane_index, :tooltip)
      # REVIEW: Change type into subclasses?

      # Find a possible mirror plane from the three standard planes.
      def pick_standard_plane(view, x, y)
        ray = view.pickray(x, y)

        @standard_plane_corners.map.with_index do |corners, index|
          screen_points = corners.map { |pt| view.screen_coords(pt) }
          next unless Geom.point_in_polygon_2D([x, y, 0], screen_points, true)

          intersection = Geom.intersect_line_plane(ray, @standard_plane_planes[index])

          # TODO: Distinguish "Component's Red" from model "Red".
          axis_name = ["red", "green", "blue"][index]

          PossiblePick.new(
            @standard_plane_planes[index],
            intersection.distance(view.camera.eye),
            :standard_plane,
            index,
            OB["flip_along_#{axis_name}"]
          )
        end.compact.min_by(&:depth)
      end

      # Find a possible mirror plane from the bounds of a selected group/instance.
      def pick_bounds_plane(view, x, y)
        ray = view.pickray(x, y)
        view.model.selection.map do |instance|
          next unless EntityHelper.instance?(instance)

          intersection =
            BoundsHelper.intersect_line(ray, instance.definition.bounds, instance.transformation)

          next unless intersection

          PossiblePick.new(
            [intersection.position, intersection.normal],
            intersection.position.distance(view.camera.eye),
            :bounds,
            nil,
            OB[:inference_on_bounds]
          )
        end.compact.min_by(&:depth)
      end

      # Find possible custom mirror plane from hovered geometry.
      def pick_custom_plane(view, _x, _y)
        # Typically flip direction is taken from a hovered face.
        # If an edge, outside of the selection, is hovered, its direction can
        # also be used. If the edge is inside of the selection, you likely don't
        # want to flip along it, as it would create an overlap.
        normal =
          if @ip.source_edge && !ip_in_selection?
            @ip.source_edge.line[1].transform(@ip.transformation)
          elsif @ip.source_face
            GeomHelper.transform_as_normal(@ip.source_face.normal, @ip.transformation)
          end

        PossiblePick.new(
            [@ip.position, normal],
            @ip.position.distance(view.camera.eye),
            :geometry,
            nil,
            @ip.tooltip
          )
      end

      # Used to pick mirror plane from hovered standard plane, bounding box or
      # entity, on mouse move.
      def pick_plane(view, x, y, normal_lock)
        # Mirror plane can be picked on hover from standard mirror planes (flip
        # along selection center), the bounds of a selected group/component, or
        # any geometry in the model.
        possible_planes = [
          pick_standard_plane(view, x, y),
          pick_bounds_plane(view, x, y),
          pick_custom_plane(view, x, y)
        ].compact.sort_by(&:depth)

        # TODO: normal_lock disables standard_plane. Maybe also bounds

        # Standard planes and geometry inside of the selection takes precedence
        # over bounds, regardless of depth.
        # Bounds can only be picked if there is empty space behind it, or some
        # other geometry that is not selected.
        if possible_planes.first.type == :bounds
          second = possible_planes[1]
          if second.type == :standard_plane || second.type == :geometry && ip_in_selection?
            possible_planes.shift
          end
        end

        picked_plane = possible_planes.first

        # REVIEW: Base the whole tool around PossiblePick struct, rather than
        # just using it locally for the pick code?
        @ip = Sketchup::InputPoint.new(picked_plane.plane[0]) unless picked_plane.type == :geometry
        @normal = picked_plane.plane[1] unless normal_lock
        @hovered_standard_plane = picked_plane.standard_plane_index
        @tooltip_text = picked_plane.tooltip
      end

      def ip_in_selection?
        !(@ip.instance_path.to_a & Sketchup.active_model.selection.to_a).empty?
      end

      # Used to pick custom direction when holding down mouse.
      def pick_direction(view, x, y)
        # If the user presses down the mouse on a standard plane, we don't want
        # to pick a custom direction.
        return if @hovered_standard_plane

        @ip_direction.pick(view, x, y, @ip)
        direction = @ip_direction.position - @ip.position
        @normal = direction if direction.valid?
        @tooltip_text = @ip_direction.tooltip
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

        init_preview_source(model)
        @normal = nil
        init_standard_planes(model.active_view)
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

      # Draw the standard planes for flipping around selection center.
      def draw_standard_planes(view)
        @standard_plane_corners.each_with_index do |points, index|
          view.drawing_color = @hovered_standard_plane == index ? FLIP_HOVER_COLOR : FLIP_COLOR
          view.draw(GL_POLYGON, points)
          view.drawing_color = FLIP_EDGE_COLOR
          view.draw(GL_LINE_LOOP, points)
        end
      end

      # Draw the "custom" mirror plane (the one from hovered geometry/bounds).
      def draw_custom_mirror_plane(view, position, normal)
        view.set_color_from_line(ORIGIN, ORIGIN.offset(normal))
        points = calculate_plane_corners(view, position, normal, PREVIEW_SIDE)
        view.draw(GL_LINE_LOOP, points)
      end

      # Get the current tool tooltip.
      def tooltip
        return @ip_direction.tooltip if @mouse_down

        @tooltip_text
      end

      # Set up cache for the untransformed state of the preview.
      # Called whenever the selection to be transformed is changed.
      def init_preview_source(model)
        # Flat array of points making up lines to preview, without any
        # mirroring.
        @preview_lines = ExtractLines.extract_lines(model.selection)
      end
    end
  end
end
