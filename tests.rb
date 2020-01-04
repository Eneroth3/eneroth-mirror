# Manual code tests.
# Select an instance (group or component) and run these snippets.

# Draw edges around invisible entity bounds.
model = Sketchup.active_model
instance = model.selection.first
pts = BoundsInfo.lines(instance.bounds)
model.start_operation("Edges", true)
pts.each { |line| model.active_entities.add_edges(line) }
model.commit_operation

# Draw edges around selection bounds.
model = Sketchup.active_model
instance = model.selection.first
pts = BoundsInfo.lines(instance.definition.bounds, instance.transformation)
model.start_operation("Edges", true)
pts.each { |line| model.active_entities.add_edges(line) }
model.commit_operation

# Draw faces around selection bounds.
model = Sketchup.active_model
instance = model.selection.first
sides = BoundsInfo.sides(instance.definition.bounds, instance.transformation)
model.start_operation("Faces", true)
sides.each { |side| model.active_entities.add_group.entities.add_face(side) }
model.commit_operation
