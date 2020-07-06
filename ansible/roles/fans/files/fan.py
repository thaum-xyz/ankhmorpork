#!/usr/bin/env python3

# Original code in https://github.com/bk4nt/pi-fan-pwm

import time
import signal
import sys
import RPi.GPIO as GPIO

FAN_PWM    = 18    # PWM input pin
FAN_TACH   = 23    # Fan's tachometer output pin
FAN_PULSES = 2     # Noctua fans puts out two pluses per revolution
FAN_FREQ   = 100   # Shall be 25kHz. See README.md

INTERVAL = 1
MIN_DUTY = 22  # Shouldn't be less than 20
MAX_TEMP = 75

TEMP_SOURCE = '/sys/class/thermal/thermal_zone0/temp'
METRICS_FILE = "/var/lib/node_exporter/fans.prom"


def signal_handler(sig, frame):
    tFile.close()
    fan.ChangeDutyCycle(100)  # Fan at full speed on exit
    GPIO.cleanup()
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

GPIO.setmode(GPIO.BCM)

GPIO.setup(18, GPIO.OUT)
fan = GPIO.PWM(FAN_PWM, FAN_FREQ)
fan.start(100)  # Start at full fan speed

GPIO.setup(FAN_TACH, GPIO.IN, pull_up_down=GPIO.PUD_UP)
t = time.time()
pulses = 0


# Count pulses on FAN_TACH pin
def fell(n):
    global t
    global pulses
    if time.time() - t > 0.005:  # Eliminate any spurious pulses
        pulses += 1
        t = time.time()


GPIO.add_event_detect(FAN_TACH, GPIO.FALLING, fell)

dc = 0

# Calculate ratio (min temp - 38C)
ratio = (100 - MIN_DUTY) / (MAX_TEMP - 38.0)
print("Startup parameters: ratio - %f, max_temp - %d, min_duty - %f" % (ratio, MAX_TEMP, MIN_DUTY))

while True:
    start = time.time()
    with open(TEMP_SOURCE) as tFile:
        temp = float(tFile.read())
    tempC = temp/1000.0

    # This should be handled by getting metrics from prometheus and using highest one
    # add 12 more degrees (value based on historical trends)
    tempC += 12

    # Tweak here minimal dc (PWM Duty Cycle), temp threshold and ratio
    dc = MIN_DUTY + max(0, int((tempC - 38) * ratio))
    dc = min(dc, 100)
    fan.ChangeDutyCycle(dc)

    rpm = pulses * 60 / (FAN_PULSES * INTERVAL)
    pulses = 0

    metrics = """# HELP fans_rpm Fan RPM
# TYPE fans_rpm gauge
fans_rpm %d
# HELP fans_duty_cycle Current duty cycle for PWM fan control
# TYPE fans_duty_cycle gauge
fans_duty_cycle %d
# HELP fans_temperature Detected temperature used as source for fan speed control
# TYPE fans_temperature gauge
fans_temperature %f
""" % (rpm, dc, tempC)

    with open(METRICS_FILE, 'w') as outFile:
        outFile.write(metrics)

    diff = time.time() - start
    time.sleep(INTERVAL - diff)
