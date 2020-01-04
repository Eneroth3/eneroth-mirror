# Test tool for previewing bounds intersection.

class TestTool
  CIRCLE_RADIUS = 50
  CIRCLE_SEGMENTS = 48

  def activate
    ###@ip = Sketchup::InputPoint.new
  end

  def deactivate(view)
    view.invalidate
  end

  def draw(view)
    return unless @point

    preview_circle(view, @point || @ip.position, @normal || Z_AXIS)

    ###@ip.draw(view)
    view.tooltip = @tooltip || @ip.tooltip
  end

  def onLButtonDown(_flags, _x, _y, view)
    return unless @point
    view.model.active_entities.add_cpoint(@point)
  end

  def onMouseMove(_flags, x, y, view)
    ###@ip.pick(view, x, y)
    @point = nil
    @tooltip = nil

    view.model.selection.clear

    # Actual flip tool would probably just look for "inference" in selected
    # instances bounds.
    # TODO: Find bounds with lowest "length".
    view.model.active_entities.each do |instance|
      next unless instance?(instance)

      result = BoundsInfo.intersect_line(view.pickray(x, y), instance.definition.bounds, instance.transformation)
      next unless result

      @point = result[0]
      @normal = result[1]
      ### @tooltip = "From Bounds"
      @tooltip = result[3].to_s

      view.model.selection.add(instance)
    end

    view.invalidate
  end

  private

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

Sketchup.active_model.select_tool(TestTool.new)
