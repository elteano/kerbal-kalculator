import std.conv;
import std.functional;
import std.math;
import std.stdio;
import std.typecons;

import gdk.Event;

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
import gtk.VBox;
import gtk.Widget;
import gtk.Window;

Builder builder;

immutable real dVC = 9.81;
immutable real con_g = 6.67E-11;

struct BodyData
{
  real mass;
  real radius;
}

BodyData[string] bodyLookup;

static this() {
  bodyLookup["Kerbin"] = BodyData(5.2915158e22, 600000);
  bodyLookup["Mun"] = BodyData(9.7599066e20, 200000);
}

void main(string[] args)
{
  Main.init(args);
  builder = new Builder("source/main.ui");
  Window win = cast(Window) builder.getObject("main-window");
  win.addOnDelete(toDelegate(&quitto));
  Button calculateButton = cast(Button) builder.getObject("calculate-button");
  calculateButton.addOnClicked(toDelegate(&onCalculate));
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
  Entry ap1Entry = cast(Entry) builder.getObject("initialApsis1");
  Entry ap2Entry = cast(Entry) builder.getObject("initialApsis2");
  ComboBoxText orbitedObject =
    cast(ComboBoxText) builder.getObject("orbited-body-combo");
  string obName = orbitedObject.getActiveText();
  auto lookup = bodyLookup[obName];
  // Do calculations
  real gm = lookup.mass * con_g;
  writefln("Mass: %f", lookup.mass);
  writefln("G: %e", con_g);
  writefln("GM: %f", gm);
  real ap1Val = to!real (ap1Entry.getText()) + lookup.radius;
  real ap2Val = to!real (ap2Entry.getText()) + lookup.radius;
  stdout.writefln("%f, %f", ap1Val, ap2Val);
  real apAvg = ap1Val / 2 + ap2Val / 2;
  real velAp1 = sqrt(gm * (2 / ap1Val - 1 / apAvg));
  real velAp2 = sqrt(gm * (2 / ap2Val - 1 / apAvg));
  stdout.writefln("%f, %f", velAp1, velAp2);
  stdout.flush();
}