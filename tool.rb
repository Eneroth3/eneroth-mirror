# Test tool for previewing bounds intersection.
#
# Hover face to pick its normal or hover bounds outside faces to pick bounds
# normal.
class TestTool
  CIRCLE_RADIUS = 50
  CIRCLE_SEGMENTS = 48

  def activate
    @ip = Sketchup::InputPoint.new
  end

  def deactivate(view)
    view.invalidate
  end

  def draw(view)
    point = @intersection&.position || @ip.position
    # TODO: Handle situation with no normal picked.
    @normal ||= Z_AXIS
    preview_circle(view, point, @normal)

    @ip.draw(view) unless @intersection
    view.tooltip = @intersection ? "From Bounds" : @ip.tooltip
  end

  def onLButtonDown(_flags, _x, _y, view)
    return unless @intersection
    view.model.active_entities.add_cpoint(@intersection.position)
  end

  def onMouseMove(_flags, x, y, view)
    @ip.pick(view, x, y)
    # Only pick from bounds if input point isn't on geometry.
    # REVIEW: Currently the presence if an @intersection dictates whether
    # point should be taken from intersection or inputpoint and tooltip
    # and stuff, spread out over different methods. Instead confine logic here
    # and just define a plane and a tooltip, and let other methods be unaware
    # of these rules.
    @intersection = @ip.degrees_of_freedom == 3 ? pick_bounds(view, x, y) : nil

    @normal = transform_as_normal(@ip.face.normal, @ip.transformation) if @ip.face
    @normal = @intersection.normal if @intersection

    view.invalidate
  end

  private

  def pick_bounds(view, x, y)
    ray = view.pickray(x, y)

    intersections = view.model.selection.map do |ins|
      next unless instance?(ins)

      BoundsInfo.intersect_line(ray, ins.definition.bounds, ins.transformation)
    end
    intersections.compact.min_by(&:distance)
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

  def transform_as_normal(normal, transformation)
    tangent = normal.axes[0].transform(transformation)
    bi_tangent = normal.axes[1].transform(transformation)

    (tangent * bi_tangent).normalize
  end
  private_class_method :transform_as_normal

end

Sketchup.active_model.select_tool(TestTool.new)
