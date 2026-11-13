"""Hotfix3 regression checks: local diagnosis and task lifecycle."""
import unittest
from pathlib import Path
from unittest.mock import patch
import test_cache_v527 as stub

app = stub.app
ROOT = Path(__file__).resolve().parent

class IntegrationContractTests(unittest.TestCase):
    def test_doctor_absent_credentials_has_precise_exit_code(self):
        with stub.tempfile.TemporaryDirectory() as d:
            with patch.object(app, 'DATA', Path(d)):
                self.assertEqual(app.doctor(), 3)

    def test_doctor_valid_credentials_and_read_only_session(self):
        class Session:
            closed = False
            def close(self): self.closed = True
        session = Session()
        with stub.tempfile.TemporaryDirectory() as d:
            with patch.object(app, 'DATA', Path(d)), \
                 patch.object(app, 'load_config_and_session', return_value=(object(), session)), \
                 patch.object(app.os, 'chdir'):
                (Path(d)/'cookies.json').write_text('FAKE TEST COOKIE')
                self.assertEqual(app.doctor(), 0)
                self.assertTrue(session.closed)

    def test_doctor_unconfirmed_session(self):
        with stub.tempfile.TemporaryDirectory() as d:
            with patch.object(app, 'DATA', Path(d)), \
                 patch.object(app, 'load_config_and_session', return_value=None), \
                 patch.object(app.os, 'chdir'):
                (Path(d)/'cookies.json').write_text('FAKE TEST COOKIE')
                self.assertEqual(app.doctor(), 4)

    def test_entrypoint_exits_and_propagates_status(self):
        batch = (ROOT/'payload/Zhidao-Task.cmd').read_text(encoding='utf-8')
        self.assertNotIn('pause', batch.lower())
        self.assertIn('goto doctor', batch)
        self.assertIn('exit /b %ERRORLEVEL%', batch)
        gui = (ROOT/'payload/Zhidao-GUI.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('function Check-TaskExit', gui)
        self.assertIn('Check-TaskExit; Check-PlayerExit', gui)
        self.assertIn("Start-Task 'doctor'", gui)
        ui = (ROOT/'payload/Zhidao-UI.xaml').read_text(encoding='utf-8-sig')
        self.assertIn('BtnDiagnose', ui)

if __name__ == '__main__':
    unittest.main(verbosity=2)
