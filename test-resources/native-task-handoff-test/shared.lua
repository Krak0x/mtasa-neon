NATIVE_HANDOFF_START = {x = 2411.3098, y = -1928.8369, z = 12.9405315, rotation = 178.7106}
NATIVE_HANDOFF_FAR = {x = 1690.0, y = 1448.0, z = 10.8}

NATIVE_HANDOFF_ROUTE = {
    {x = 2410.7388, y = -1960.0266, z = 12.3906, speed = 13.0},
    {x = 2326.9031, y = -1969.6761, z = 12.3738, speed = 15.0},
    {x = 2235.2625, y = -1891.3008, z = 12.3828, speed = 18.0},
    {x = 2094.3066, y = -1891.8560, z = 12.3738, speed = 18.0},
    {x = 2105.8198, y = -1754.1766, z = 12.3984, speed = 20.0},
    {x = 2321.9136, y = -1736.0938, z = 12.3828, speed = 20.0},
    {x = 2498.3200, y = -1658.2800, z = 12.3600, speed = 20.0},
    {x = 2502.8900, y = -1674.7100, z = 12.3700, speed = 15.0},
}

for _, point in ipairs(NATIVE_HANDOFF_ROUTE) do
    point.task = "drive_to"
    point.mode = "normal"
    point.vehicleModel = 412
    point.drivingStyle = "avoid_cars"
end
