import std.algorithm;
import std.conv;
import std.file;
import std.format;
import std.functional;
import std.json;
import std.math;
import std.stdio;
import std.typecons;

import gdk.Event;
import gdk.RGBA;

import gtk.Builder;
import gtk.Button;
import gtk.ComboBoxText;
import gtk.Container;
import gtk.Entry;
import gtk.Frame;
import gtk.Grid;
import gtk.HBox;
import gtk.Label;
import gtk.Main;
import gtk.MainWindow;
import gtk.TextView;
import gtk.VBox;
import gtk.Widget;
import gtk.Window;

Builder builder;

immutable real dVC = 9.81;
immutable real con_g = 6.67E-11;

RGBA COLOR_RED;
RGBA COLOR_BLACK;
RGBA COLOR_CLEAR;

struct BodyData
{
  real mass;
  real radius;
}

BodyData[string] bodyLookup;

void main(string[] args)
{
  COLOR_RED = new RGBA(.9, .1, .1);
  COLOR_BLACK = new RGBA(0, 0, 0, 1);
  COLOR_CLEAR = new RGBA();

  Main.init(args);
  builder = new Builder("main.ui");
  Window win = cast(Window) builder.getObject("main-window");
  win.addOnDelete(toDelegate(&quitto));

  //
  // Setup Oribttal calculation
  //
  Button calculateButton = cast(Button) builder.getObject("calculate-button");
  // Load Json
  auto val = parseJSON(cast(char[])read("planets.json"));
  ComboBoxText planetsCombo = cast(ComboBoxText) builder.getObject("orbited-body-combo");
  foreach (planet; val.array)
  {
    planetsCombo.appendText(planet["name"].str);
    bodyLookup[planet["name"].str] = BodyData(planet["mass"].get!real, planet["radius"].get!real);
  }
  planetsCombo.setActive(0);
  calculateButton.addOnClicked(toDelegate(&onCalculate));

  //
  // Setup Delta V calculation
  //
  Button dvCalculateButton = cast(Button) builder.getObject("calc-dv-button");
  dvCalculateButton.addOnClicked(toDelegate(&onCalculateDv));

  win.showAll();
  Main.run();
}

bool quitto(Event event, Widget widget)
{
  Main.quit();
  return false;
}

void onCalculate(Button button)
{
  real apI1Val, apI2Val, apE1Val, apE2Val;
  Entry apI1Entry = cast(Entry) builder.getObject("initialApsis1");
  Entry apI2Entry = cast(Entry) builder.getObject("initialApsis2");
  Entry apE1Entry = cast(Entry) builder.getObject("endApsis1");
  Entry apE2Entry = cast(Entry) builder.getObject("endApsis2");
  ComboBoxText orbitedObject =
    cast(ComboBoxText) builder.getObject("orbited-body-combo");
  string obName = orbitedObject.getActiveText();
  auto lookup = bodyLookup[obName];
  // Do calculations
  bool apI1Good = tryGetRealFromEntry("initialApsis1", apI1Val);
  apI1Val += lookup.radius;
  bool apI2Good = tryGetRealFromEntry("initialApsis2", apI2Val);
  apI2Val += lookup.radius;

  bool apE1Good = tryGetRealFromEntry("endApsis1", apE1Val);
  apE1Val += lookup.radius;
  bool apE2Good = tryGetRealFromEntry("endApsis2", apE2Val);
  apE2Val += lookup.radius;

  if (apI1Good && apI2Good && apE1Good && apE2Good)
  {
    auto vels = calculateVelocities(apI1Val, apI2Val, lookup.mass);
    auto vels2 = calculateVelocities(apE1Val, apE2Val, lookup.mass);
    auto raise1 = calculateDeltaVShift(apI1Val, apI2Val, apE2Val, lookup.mass);

    updateVelocityLabel("init1Vel", vels[0]);
    updateVelocityLabel("init2Vel", vels[1]);
    updateVelocityLabel("end1Vel", vels2[0]);
    updateVelocityLabel("end2Vel", vels2[1]);

    auto vels1_1 = calculateVelocities(apI1Val, apE1Val, lookup.mass);
    auto vels1_2 = calculateVelocities(apI1Val, apE2Val, lookup.mass);
    auto vels2_1 = calculateVelocities(apI2Val, apE1Val, lookup.mass);
    auto vels2_2 = calculateVelocities(apI2Val, apE2Val, lookup.mass);

    real[] dv1_1 = [abs(vels[0] - vels1_1[0]), abs(vels1_1[1] - vels2[0])];
    real[] dv1_2 = [abs(vels[0] - vels1_2[0]), abs(vels1_2[1] - vels2[1])];
    real[] dv2_1 = [abs(vels[1] - vels2_1[0]), abs(vels2_1[1] - vels2[0])];
    real[] dv2_2 = [abs(vels[1] - vels2_2[0]), abs(vels2_2[1] - vels2[1])];
    auto dv_sums = [sum(dv1_1), sum(dv1_2), sum(dv2_1), sum(dv2_2)];
    auto dv_lookup = [dv1_1, dv1_2, dv2_1, dv2_2];
    auto vels_lookup = [
      [vels1_1[0], vels2[0]],
      [vels1_2[0], vels2[1]],
      [vels2_1[0], vels2[0]],
      [vels2_2[0], vels2[1]],
    ];

    auto mInd = minIndex(dv_sums);
    auto min = dv_sums[mInd];
    size_t firstBurnPoint = mInd / 2 + 1;
    auto firstBurnAmount = dv_lookup[mInd][0];
    auto secondBurnAmount = dv_lookup[mInd][1];
    auto firstBurnDest = vels_lookup[mInd][0];
    auto secondBurnDest = vels_lookup[mInd][1];

    updateVelocityLabel("req-dv", min);

    string fulltext = format("Start at point %d. Burn %.2f dV to a target " ~
                             "velocity of %.2f. At the other point, burn by " ~
                             "%.2f dV to a target velocity of %.2f.",
                             firstBurnPoint, firstBurnAmount, firstBurnDest,
                             secondBurnAmount, secondBurnDest);
    TextView instructions = cast(TextView) builder.getObject("instructions");
    instructions.getBuffer().setText(fulltext);
    stdout.writeln(fulltext);
    stdout.flush();
  }
}

void updateVelocityLabel(string labelId, real vel)
{
  Label label = cast(Label) builder.getObject(labelId);
  label.setText(format("%.2f", vel));
}

Tuple!(real, real) calculateVelocities(real apsis1, real apsis2, real bodyMass)
{
  real gm = bodyMass * con_g;
  real apAvg = apsis1 / 2 + apsis2 / 2;
  real velAp1 = sqrt(gm * (2 / apsis1 - 1 / apAvg));
  real velAp2 = sqrt(gm * (2 / apsis2 - 1 / apAvg));
  return Tuple!(real, real)(velAp1, velAp2);
}

real calculateDeltaVShift(real apoFire, real apoStart, real apoEnd, real bodyMass)
{
  auto init_vels = calculateVelocities(apoFire, apoStart, bodyMass);
  auto end_vels = calculateVelocities(apoFire, apoEnd, bodyMass);
  return abs(init_vels[0] - end_vels[0]);
}

bool tryGetRealFromEntry(string id, out real val)
{
  Entry getMe = cast(Entry) builder.getObject(id);
  try
  {
    val = to!real (getMe.getText());
  }
  catch (ConvException e)
  {
    getMe.overrideBackgroundColor(cast(GtkStateFlags) 0, COLOR_RED);
    return false;
  }
  getMe.overrideBackgroundColor(cast(GtkStateFlags) 0, COLOR_CLEAR);
  return true;
}

void onCalculateDv(Button button)
{
  real inputIsp, inputWetMass, inputDryMass, calcDv;
  Label outputLabel;

  outputLabel = cast(Label) builder.getObject("calc-dv-label");
  // Perform conversions
  bool ispGood = tryGetRealFromEntry("isp-entry", inputIsp);
  bool wetGood = tryGetRealFromEntry("wet-mass-entry", inputWetMass);
  bool dryGood = tryGetRealFromEntry("dry-mass-entry", inputDryMass);
  if (ispGood && wetGood && dryGood)
  {
    calcDv = calculateShipDeltaV(inputIsp, inputWetMass, inputDryMass);
    outputLabel.setText(format("%.2f", calcDv));
  }
}

real calculateShipDeltaV(real isp, real wetMass, real dryMass)
{
  return dVC * isp * log(wetMass / dryMass);
}