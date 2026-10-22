using System;
using System.IO;
using System.Windows.Forms;
using DF3D.Release;

public static class SetupUiTests {
 [STAThread] public static int Main(string[] args) {
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
  Application.Run(new Launcher(args[0],args[1]));return 0;
 }
}
