-- Personal input overrides. Omarchy defaults load first.

hl.config({
  input = {
    repeat_delay = 600,
  },
})

hl.device({
  name = "tpps/2-elan-trackpoint",
  sensitivity = 0.5,
  accel_profile = "flat",
})

hl.device({
  name = "glorious-model-d-2-pro",
  sensitivity = 0,
  accel_profile = "flat",
})
