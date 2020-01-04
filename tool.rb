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
    results = view.model.active_entities.map do |instance|
      next unless instance?(instance)

      result = BoundsInfo.intersect_line(view.pickray(x, y), instance.definition.bounds, instance.transformation)
      next unless result

      result << instance
    end
    result = results.compact.min_by { |r| r[2] }
    return unless result

    @point = result[0]
    @normal = result[1]
    ### @tooltip = "From Bounds"
    @tooltip = result[2].to_s

    view.model.selection.add(result[4])

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
