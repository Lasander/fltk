//
// "$Id$"
//
// MacOS system menu bar widget for the Fast Light Tool Kit (FLTK).
//
// Copyright 1998-2017 by Bill Spitzak and others.
//
// This library is free software. Distribution and use rights are outlined in
// the file "COPYING" which should have been included with this file.  If this
// file is missing or damaged, see the license at:
//
//     http://www.fltk.org/COPYING.php
//
// Please report all bugs and problems on the following page:
//
//     http://www.fltk.org/str.php
//

#if defined(__APPLE__)

#include <FL/Fl_Sys_Menu_Bar_Driver.H>
#include <FL/x.H>
#include "drivers/Cocoa/Fl_MacOS_Sys_Menu_Bar_Driver.H"


Fl_MacOS_Sys_Menu_Bar_Driver* Fl_MacOS_Sys_Menu_Bar_Driver::new_driver() {
  static Fl_MacOS_Sys_Menu_Bar_Driver *once = new Fl_MacOS_Sys_Menu_Bar_Driver();
  if (Fl_Sys_Menu_Bar_Driver::driver_ != once) {
    if (Fl_Sys_Menu_Bar_Driver::driver_) {
      once->bar = Fl_Sys_Menu_Bar_Driver::driver_->bar;
      delete Fl_Sys_Menu_Bar_Driver::driver_;
    }
    Fl_Sys_Menu_Bar_Driver::driver_ = once;
    if (Fl_Sys_Menu_Bar_Driver::driver_->bar) Fl_Sys_Menu_Bar_Driver::driver_->bar->update();
  }
  return once;
}

// this runs once if this source file is linked in, and initializes the
// static variable Fl_Sys_Menu_Bar_Driver::driver_ with an object of class Fl_MacOS_Sys_Menu_Bar_Driver
static Fl_MacOS_Sys_Menu_Bar_Driver *unused = Fl_MacOS_Sys_Menu_Bar_Driver::new_driver();


#import <Cocoa/Cocoa.h>

#include "flstring.h"
#include <stdio.h>
#include <ctype.h>
#include <stdarg.h>

typedef const Fl_Menu_Item *pFl_Menu_Item;

static Fl_Menu_Bar *custom_menu;

static char *remove_ampersand(const char *s);
extern void (*fl_lock_function)();
extern void (*fl_unlock_function)();

/*  Each MacOS system menu item contains a pointer to a record of type sys_menu_item defined below.
    The purpose of these records is to associate each MacOS system menu item with a relevant Fl_Menu_Item.

    If use_index is YES, the "index" field is used, and fl_sys_menu_bar->menu() + index is the address
    of the relevant Fl_Menu_Item;
    Otherwise, the "item" field points to the relevant Fl_Menu_Item.
    This allows the MacOS system menu to use the same Fl_Menu_Item's as those used by FLTK menus, 
    the address of which can be relocated by the FLTK menu logic.
    The "item" field is used for non-relocatable Fl_Menu_Item's associated to FL_SUBMENU_POINTER.
    Sending the getFlItem message to a MacOS system menu item (of class FLMenuItem) returns the address
    of the relevant Fl_Menu_Item.
*/
typedef struct {
  union {
    int index;
    const Fl_Menu_Item *item;
  };
  BOOL use_index;
} sys_menu_item;

// Apple App Menu
const char *Fl_Mac_App_Menu::about = "About %@";
const char *Fl_Mac_App_Menu::print = "Print Front Window";
const char *Fl_Mac_App_Menu::services = "Services";
const char *Fl_Mac_App_Menu::hide = "Hide %@";
const char *Fl_Mac_App_Menu::hide_others = "Hide Others";
const char *Fl_Mac_App_Menu::show = "Show All";
const char *Fl_Mac_App_Menu::quit = "Quit %@";


@interface FLMenuItem : NSMenuItem {
}
- (const Fl_Menu_Item*) getFlItem;
- (void) itemCallback:(Fl_Menu_*)menu;
- (void) doCallback;
- (void) customCallback;
- (void) directCallback;
- (void) setKeyEquivalentModifierMask:(int)value;
- (void) setFltkShortcut:(int)key;
+ (int) addNewItem:(const Fl_Menu_Item*)mitem menu:(NSMenu*)menu action:(SEL)selector;
@end

@implementation FLMenuItem
- (const Fl_Menu_Item*) getFlItem
// returns the Fl_Menu_Item corresponding to this system menu item
{
  sys_menu_item *smi = (sys_menu_item*)[(NSData*)[self representedObject] bytes];
  if (smi->use_index) return fl_sys_menu_bar->menu() + smi->index;
  return smi->item;
}
- (void) itemCallback:(Fl_Menu_*)menu
{
  const Fl_Menu_Item *item = [self getFlItem];
  menu->picked(item);
  if ( item->flags & FL_MENU_TOGGLE ) {	// update the menu toggle symbol
    [self setState:(item->value() ? NSOnState : NSOffState)];
  }
  else if ( item->flags & FL_MENU_RADIO ) {	// update the menu radio symbols
    NSMenu* menu = [self menu];
    NSInteger flRank = [menu indexOfItem:self];
    NSInteger last = [menu numberOfItems] - 1;
    int from = flRank;
    while(from > 0) {
      if ([[menu itemAtIndex:from-1] isSeparatorItem]) break;
      item = [(FLMenuItem*)[menu itemAtIndex:from-1] getFlItem];
      if ( !(item->flags & FL_MENU_RADIO) ) break;
      from--;
    }
    int to = flRank;
    while (to < last) {
      if ([[menu itemAtIndex:to+1] isSeparatorItem]) break;
      item = [(FLMenuItem*)[menu itemAtIndex:to+1] getFlItem];
      if (!(item->flags & FL_MENU_RADIO)) break;
      to++;
    }
    for(int i =  from; i <= to; i++) {
      NSMenuItem *nsitem = [menu itemAtIndex:i];
      [nsitem setState:(nsitem != self ? NSOffState : NSOnState)];
    }
  }
}
- (void) doCallback
{
  fl_lock_function();
  [self itemCallback:fl_sys_menu_bar];
  fl_unlock_function();
}
- (void) customCallback
{
  fl_lock_function();
  [self itemCallback:custom_menu];
  fl_unlock_function();
}
- (void) directCallback
{
  fl_lock_function();
  Fl_Menu_Item *item = (Fl_Menu_Item *)[(NSData*)[self representedObject] bytes];
  if ( item && item->callback() ) item->do_callback(NULL);
  fl_unlock_function();
}
- (void) setKeyEquivalentModifierMask:(int)value
{
  NSUInteger macMod = 0;
  if ( value & FL_META ) macMod = NSCommandKeyMask;
  if ( value & FL_SHIFT || isupper(value) ) macMod |= NSShiftKeyMask;
  if ( value & FL_ALT ) macMod |= NSAlternateKeyMask;
  if ( value & FL_CTRL ) macMod |= NSControlKeyMask;
  [super setKeyEquivalentModifierMask:macMod];
}
- (void) setFltkShortcut:(int)key
{
  // Separate key and modifier
  int mod = key;
  mod &= ~FL_KEY_MASK;	// modifier(s)
  key &=  FL_KEY_MASK;	// key
  unichar mac_key = (unichar)key;
  if ( (key >= (FL_F+1)) && (key <= FL_F_Last) ) { // Handle function keys
    int fkey_num = (key - FL_F);	// 1,2..
    mac_key = NSF1FunctionKey + fkey_num - 1;
    }
  [self setKeyEquivalent:[NSString stringWithCharacters:&mac_key length:1]];
  [self setKeyEquivalentModifierMask:mod];
}
+ (int) addNewItem:(const Fl_Menu_Item*)mitem menu:(NSMenu*)menu action:(SEL)selector
{
  char *name = remove_ampersand(mitem->label());
  NSString *title = NSLocalizedString([NSString stringWithUTF8String:name], nil);
  free(name);
  FLMenuItem *item = [[FLMenuItem alloc] initWithTitle:title
						action:selector
					 keyEquivalent:@""];
  sys_menu_item smi;
  // >= 0 if mitem is in the menu items of fl_sys_menu_bar, -1 if not
  smi.index = (fl_sys_menu_bar ? fl_sys_menu_bar->find_index(mitem) : -1);
  smi.use_index = (smi.index >= 0);
  if (!smi.use_index) smi.item = mitem;
  NSData *pointer = [NSData dataWithBytes:&smi length:sizeof(smi)];
  [item setRepresentedObject:pointer];
  [menu addItem:item];
  [item setTarget:item];
  int retval = [menu indexOfItem:item];
  [item release];
  return retval;
}
@end

 
void Fl_MacOS_Sys_Menu_Bar_Driver::about( Fl_Callback *cb, void *user_data)
{
  fl_open_display();
  Fl_Menu_Item aboutItem;
  memset(&aboutItem, 0, sizeof(Fl_Menu_Item));
  aboutItem.callback(cb);
  aboutItem.user_data(user_data);
  NSMenu *appleMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
  CFStringRef cfname = CFStringCreateCopy(NULL, (CFStringRef)[[appleMenu itemAtIndex:0] title]);
  [appleMenu removeItemAtIndex:0];
  FLMenuItem *item = [[[FLMenuItem alloc] initWithTitle:(NSString*)cfname 
						 action:@selector(directCallback)
					  keyEquivalent:@""] autorelease];
  NSData *pointer = [NSData dataWithBytes:&aboutItem length:sizeof(Fl_Menu_Item)];
  [item setRepresentedObject:pointer];
  [appleMenu insertItem:item atIndex:0];
  CFRelease(cfname);
  [item setTarget:item];
}

/*
 * Set a shortcut for an Apple menu item using the FLTK shortcut descriptor.
 */
static void setMenuShortcut( NSMenu* mh, int miCnt, const Fl_Menu_Item *m )
{
  if ( !m->shortcut_ ) 
    return;
  if ( m->flags & FL_SUBMENU )
    return;
  if ( m->flags & FL_SUBMENU_POINTER )
    return;
  FLMenuItem* menuItem = (FLMenuItem*)[mh itemAtIndex:miCnt];
  [menuItem setFltkShortcut:(m->shortcut_)];
}


/*
 * Set the Toggle and Radio flag based on FLTK flags
 */
static void setMenuFlags( NSMenu* mh, int miCnt, const Fl_Menu_Item *m )
{
  if ( m->flags & FL_MENU_TOGGLE )
  {
    NSMenuItem *menuItem = [mh itemAtIndex:miCnt];
    [menuItem setState:(m->flags & FL_MENU_VALUE ? NSOnState : NSOffState)];
  }
  else if ( m->flags & FL_MENU_RADIO ) {
    NSMenuItem *menuItem = [mh itemAtIndex:miCnt];
    [menuItem setState:(m->flags & FL_MENU_VALUE ? NSOnState : NSOffState)];
  }
}

static char *remove_ampersand(const char *s)
{
  char *ret = strdup(s);
  const char *p = s;
  char *q = ret;
  while(*p != 0) {
    if (p[0]=='&') {
      if (p[1]=='&') {
        *q++ = '&'; p+=2;
      } else {
        p++;
      }
    } else {
      *q++ = *p++;
    }
  }
  *q = 0;
  return ret;
}


/*
 * create a sub menu for a specific menu handle
 */
static void createSubMenu( NSMenu *mh, pFl_Menu_Item &mm,  const Fl_Menu_Item *mitem, SEL selector)
{
  NSMenu *submenu;
  int miCnt, flags;
  
  if (mitem) {
    NSMenuItem *menuItem;
    char *ts = remove_ampersand(mitem->text);
    NSString *title = NSLocalizedString([NSString stringWithUTF8String:ts], nil);
    free(ts);
    submenu = [[NSMenu alloc] initWithTitle:(NSString*)title];
    [submenu setAutoenablesItems:NO];
    
    int cnt;
    cnt = [mh numberOfItems];
    cnt--;
    menuItem = [mh itemAtIndex:cnt];
    [menuItem setSubmenu:submenu];
    [submenu release];
  } else submenu = mh;
  
  while ( mm->text ) {
    if (!mm->visible() ) { // skip invisible items and submenus
      mm = mm->next(0);
      continue;
    }
    miCnt = [FLMenuItem addNewItem:mm menu:submenu action:selector];
    setMenuFlags( submenu, miCnt, mm );
    setMenuShortcut( submenu, miCnt, mm );
    if (mitem && (mm->flags & FL_MENU_INACTIVE || mitem->flags & FL_MENU_INACTIVE)) {
      NSMenuItem *item = [submenu itemAtIndex:miCnt];
      [item setEnabled:NO];
    }
    flags = mm->flags;
    if ( mm->flags & FL_SUBMENU )
    {
      mm++;
      createSubMenu( submenu, mm, mm - 1, selector);
    }
    else if ( mm->flags & FL_SUBMENU_POINTER )
    {
      const Fl_Menu_Item *smm = (Fl_Menu_Item*)mm->user_data_;
      createSubMenu( submenu, smm, mm, selector);
    }
    if ( flags & FL_MENU_DIVIDER ) {
      [submenu addItem:[NSMenuItem separatorItem]];
      }
    mm++;
  }
}
 

/*
 * convert a complete Fl_Menu_Item array into a series of menus in the top menu bar
 * ALL PREVIOUS SYSTEM MENUS, EXCEPT THE APPLICATION MENU, ARE REPLACED BY THE NEW DATA
 */
static void convertToMenuBar(const Fl_Menu_Item *mm)
{
  NSMenu *fl_system_menu = [NSApp mainMenu];
  int count;//first, delete all existing system menus
  count = [fl_system_menu numberOfItems];
  for(int i = count - 1; i > 0; i--) {
    [fl_system_menu removeItem:[fl_system_menu itemAtIndex:i]];
  }
  if (mm) createSubMenu(fl_system_menu, mm, NULL, @selector(doCallback));
}

void Fl_MacOS_Sys_Menu_Bar_Driver::update()
{
  convertToMenuBar(bar->Fl_Menu_::menu());
}


static int process_sys_menu_shortcuts(int event)
{
  if (event != FL_SHORTCUT || !fl_sys_menu_bar || Fl::modal()) return 0;
  // is the last event the shortcut of an item of the fl_sys_menu_bar menu ?
  const Fl_Menu_Item *item = fl_sys_menu_bar->menu()->test_shortcut();
  if (!item) return 0;
  if (item->visible()) // have the system menu process the shortcut, highlighting the corresponding menu
    [[NSApp mainMenu] performKeyEquivalent:[NSApp currentEvent]];
  else // have FLTK process the shortcut associated to an invisible Fl_Menu_Item
    fl_sys_menu_bar->picked(item);
  return 1;
}

Fl_MacOS_Sys_Menu_Bar_Driver::Fl_MacOS_Sys_Menu_Bar_Driver() : Fl_Sys_Menu_Bar_Driver()
{
  Fl::add_handler(process_sys_menu_shortcuts);
}

Fl_MacOS_Sys_Menu_Bar_Driver::~Fl_MacOS_Sys_Menu_Bar_Driver()
{
  Fl::remove_handler(process_sys_menu_shortcuts);
}

void Fl_MacOS_Sys_Menu_Bar_Driver::menu(const Fl_Menu_Item *m)
{
  fl_open_display();
  bar->Fl_Menu_Bar::menu( m );
  convertToMenuBar(m);
}

void Fl_MacOS_Sys_Menu_Bar_Driver::clear()
{
  bar->Fl_Menu_::clear();
  convertToMenuBar(NULL);
}

int Fl_MacOS_Sys_Menu_Bar_Driver::clear_submenu(int index)
{
  int retval = bar->Fl_Menu_::clear_submenu(index);
  if (retval != -1) update();
  return retval;
}

void Fl_MacOS_Sys_Menu_Bar_Driver::remove(int index)
{
  bar->Fl_Menu_::remove(index);
  update();
}

void Fl_MacOS_Sys_Menu_Bar_Driver::replace(int index, const char *name)
{
  bar->Fl_Menu_::replace(index, name);
  update();
}

void Fl_MacOS_Sys_Menu_Bar_Driver::mode(int i, int fl) {
  bar->Fl_Menu_::mode(i, fl);
  update();
}

void Fl_MacOS_Sys_Menu_Bar_Driver::shortcut (int i, int s) {
  bar->Fl_Menu_Bar::shortcut(i, s);
  update();
}

void Fl_MacOS_Sys_Menu_Bar_Driver::setonly (Fl_Menu_Item *item) {
  bar->Fl_Menu_::setonly(item);
  update();
}

int Fl_MacOS_Sys_Menu_Bar_Driver::add(const char* label, int shortcut, Fl_Callback *cb, void *user_data, int flags)
{
  fl_open_display();
  int index = bar->Fl_Menu_::add(label, shortcut, cb, user_data, flags);
  update();
  return index;
}

int Fl_MacOS_Sys_Menu_Bar_Driver::add(const char* str)
{
  fl_open_display();
  int index = bar->Fl_Menu_::add(str);
  update();
  return index;
}

int Fl_MacOS_Sys_Menu_Bar_Driver::insert(int index, const char* label, int shortcut, Fl_Callback *cb, void *user_data, int flags)
{
  fl_open_display();
   int menu_index = bar->Fl_Menu_::insert(index, label, shortcut, cb, user_data, flags);
   update();
   return menu_index;
}

/** \class Fl_Mac_App_Menu
 Mac OS-specific class allowing to customize and localize the application menu.
 
 The public class attributes are used to build the application menu. They can be localized
 at run time to any UTF-8 text by placing instructions such as this before fl_open_display()
 gets called:
 \verbatim
 Fl_Mac_App_Menu::print = "Imprimer la fenêtre";
 \endverbatim
 \see \ref osissues_macos for another way to localization.
 */


/** Adds custom menu item(s) to the application menu of the system menu bar.
 They are positioned after the "Print Front Window" item, or at its place
 if it was removed with <tt>Fl_Mac_App_Menu::print = ""</tt>.
 \param m zero-ending array of Fl_Menu_Item 's.
 */
void Fl_Mac_App_Menu::custom_application_menu_items(const Fl_Menu_Item *m)
{
  fl_open_display(); // create the system menu, if needed
  custom_menu = new Fl_Menu_Bar(0,0,0,0);
  custom_menu->menu(m);
  NSMenu *menu = [[[NSApp mainMenu] itemAtIndex:0] submenu]; // the application menu
  NSInteger to_index;
  if ([[menu itemAtIndex:2] action] != @selector(printPanel)) { // the 'Print' item was removed
    [menu insertItem:[NSMenuItem separatorItem] atIndex:1];
    to_index = 2;
  } else to_index = 3; // after the "Print Front Window" item
  NSInteger count = [menu numberOfItems];
  createSubMenu(menu, m, NULL, @selector(customCallback)); // add new items at end of application menu
  NSInteger count2 = [menu numberOfItems];
  for (NSInteger i = count; i < count2; i++) { // move new items to their desired position in application menu
    NSMenuItem *item = [menu itemAtIndex:i];
    [item retain];
    [menu removeItemAtIndex:i];
    [menu insertItem:item atIndex:to_index++];
    [item release];
  }
}
#endif /* __APPLE__ */

//
// End of "$Id$".
//