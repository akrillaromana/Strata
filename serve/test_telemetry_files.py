"""No-hardware checks: Linux telemetry fallback closes /proc handles on success and failure."""
import io
import unittest
from unittest.mock import patch

from serve import telemetry


class TrackingText(io.StringIO):
    closed_by_context = False

    def __exit__(self, *args):
        self.closed_by_context = True
        return super().__exit__(*args)


class ProcHandles(unittest.TestCase):
    def test_cpu_model_file_closed(self):
        stream = TrackingText('processor : 0\nmodel name : Synthetic CPU\n')
        original = open

        def fake(path, *args, **kwargs):
            if path == '/proc/cpuinfo':
                return stream
            return original(path, *args, **kwargs)

        with patch.object(telemetry.os.path, 'exists', return_value=True), \
             patch.object(telemetry.os, 'name', 'posix'), patch('builtins.open', side_effect=fake):
            self.assertEqual(telemetry._cpu_name(), 'Synthetic CPU')
        self.assertTrue(stream.closed_by_context)

    def test_cpu_stat_handle_closed(self):
        stream = TrackingText('cpu  1 2 3 4 5 6 7 8\n')
        original = open

        def fake(path, *args, **kwargs):
            return stream if path == '/proc/stat' else original(path, *args, **kwargs)

        with patch.object(telemetry.os, 'name', 'posix'), patch('builtins.open', side_effect=fake):
            self.assertEqual(telemetry._CpuRamFallback._times(telemetry._CpuRamFallback.__new__(telemetry._CpuRamFallback)),
                             (9, 36))
        self.assertTrue(stream.closed_by_context)

    def test_ram_info_handle_closed(self):
        stream = TrackingText('MemTotal: 1000 kB\nMemAvailable: 300 kB\n')
        original = open

        def fake(path, *args, **kwargs):
            return stream if path == '/proc/meminfo' else original(path, *args, **kwargs)

        with patch.object(telemetry.os, 'name', 'posix'), patch('builtins.open', side_effect=fake):
            self.assertEqual(telemetry._CpuRamFallback.ram(), (700 * 1024, 1000 * 1024))
        self.assertTrue(stream.closed_by_context)


if __name__ == '__main__':
    unittest.main()
