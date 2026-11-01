local names = {
  [0x0] = "widget_accelerate",
  [0x1] = "widget_enter_car",
  [0x2] = "widget_move_stick",
  [0x3] = "widget_look_around",
  [0x4] = "widget_aim_melee_gun",
  [0x5] = "widget_gun",
  [0x6] = "widget_gun_second",
  [0x7] = "widget_brake",
  [0x8] = "widget_handbrake",
  [0x9] = "widget_horn",
  [0xA] = "widget_highbeam_switch",
  [0xB] = "widget_passenger_entercar",
  [0xC] = "widget_voice",
  [0xD] = "widget_car_camera",
  [0xE] = "widget_move_left",
  [0xF] = "widget_move_right",
  [0x10] = "widget_nitro",
  [0x11] = "widget_hydraulic",
  [0x12] = "widget_dive",
  [0x13] = "widget_zoom_plus",
  [0x14] = "widget_zoom_minus",
  [0x15] = "widget_rotate_left",
  [0x16] = "widget_rotate_right",
  [0x17] = "widget_driveby",
  [0x18] = "widget_towtruck_hook_up",
  [0x19] = "widget_towtruck_hook_down",
  [0x1A] = "widget_radar",
  [0x1B] = "widget_player_info",
  [0x1C] = "widget_zoom_in",
  [0x1D] = "widget_zoom_out",
  [0x1E] = "widget_fist",
  [0x1F] = "widget_car_shoot",
  [0x20] = "widget_vehicle_steer_analog",
  [0x21] = "widget_portal_in",
  [0x22] = "widget_hud_car_lock",
}

local widgets = {
  -- Primary ag-client widget constants (slots 0..34)
  WIDGET_ACCELERATE = 0x0,
  WIDGET_ENTER_CAR = 0x1,
  WIDGET_MOVE_STICK = 0x2,
  WIDGET_LOOK_AROUND = 0x3,
  WIDGET_AIM_MELEE_GUN = 0x4,
  WIDGET_GUN = 0x5,
  WIDGET_GUN_SECOND = 0x6,
  WIDGET_BRAKE = 0x7,
  WIDGET_HANDBRAKE = 0x8,
  WIDGET_HORN = 0x9,
  WIDGET_HIGHBEAM_SWITCH = 0xA,
  WIDGET_PASSENGER_ENTERCAR = 0xB,
  WIDGET_VOICE = 0xC,
  WIDGET_CAR_CAMERA = 0xD,
  WIDGET_MOVE_LEFT = 0xE,
  WIDGET_MOVE_RIGHT = 0xF,
  WIDGET_NITRO = 0x10,
  WIDGET_HYDRAULIC = 0x11,
  WIDGET_DIVE = 0x12,
  WIDGET_ZOOM_PLUS = 0x13,
  WIDGET_ZOOM_MINUS = 0x14,
  WIDGET_ROTATE_LEFT = 0x15,
  WIDGET_ROTATE_RIGHT = 0x16,
  WIDGET_DRIVEBY = 0x17,
  WIDGET_TOWTRUCK_HOOK_UP = 0x18,
  WIDGET_TOWTRUCK_HOOK_DOWN = 0x19,
  WIDGET_RADAR = 0x1A,
  WIDGET_PLAYER_INFO = 0x1B,
  WIDGET_ZOOM_IN = 0x1C,
  WIDGET_ZOOM_OUT = 0x1D,
  WIDGET_FIST = 0x1E,
  WIDGET_CAR_SHOOT = 0x1F,
  WIDGET_VEHICLE_STEER_ANALOG = 0x20,
  WIDGET_PORTAL_IN = 0x21,
  WIDGET_HUD_CAR_LOCK = 0x22,

  -- Compatibility aliases for legacy scripts
  WIDGET_ATTACK = 0x4,
  WIDGET_PED_MOVE = 0x2,
  WIDGET_SPRINT = 0x0,
  WIDGET_BUTTON_SPRINT = 0x0,
  WIDGET_BUTTON_SWIM = 0x0,
  WIDGET_BUTTON_DIVE = 0x12,
  WIDGET_BUTTON_CROUCH = 0x12,
  WIDGET_HYDRAULICS = 0x11,
  WIDGET_AUTO_HYDRAULICS = 0x11,
  WIDGET_AIR_GUN = 0x8,
  WIDGET_ENTER_TARGETING = 0x4,
  WIDGET_EXIT_TARGETING = 0x4,
  WIDGET_BASKETBALL_JUMP = 0x0,
  WIDGET_MISSION_START_VIGILANTE = 0x9,
  WIDGET_MISSION_CANCEL_VIGILANTE = 0x9,
  WIDGET_MISSION_START = 0x9,
  WIDGET_MISSION_CANCEL = 0x9,
  WIDGET_VEHICLE_STEER_LEFT = 0xE,
  WIDGET_VEHICLE_STEER_RIGHT = 0xF,
  WIDGET_CAM_TOGGLE = 0xD,
  WIDGET_PHONE = 0x9,
  WIDGET_LOOK = 0x3,
  WIDGET_HELP_TEXT = 0x1B,

  NUM_WIDGETS = 35,
  count = 35,
  names = names,
  getName = function(id)
    return names[id]
  end,
}

setmetatable(widgets, {
  __index = function(t, k)
    if type(k) == "number" then
      return names[k]
    end
    return nil
  end
})

for k, v in pairs(widgets) do
  _G[k] = v
end

return widgets
