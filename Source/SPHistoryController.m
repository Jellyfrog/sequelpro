//
//  $Id$
//
//  SPHistoryController.m
//  sequel-pro
//
//  Created by Rowan Beentje on July 23, 2009
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation; either version 2 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
//
//  More info at <http://code.google.com/p/sequel-pro/>

#import "TableDocument.h"
#import "TableContent.h"
#import "TablesList.h"
#import "SPHistoryController.h"
#import "SPStringAdditions.h"

@implementation SPHistoryController

@synthesize history;
@synthesize historyPosition;
@synthesize modifyingHistoryState;

#pragma mark Setup and teardown

/**
 * Initialise by creating a blank history array
 */
- (id) init
{
	if (self = [super init]) {
		history = [[NSMutableArray alloc] init];
		tableContentStates = [[NSMutableDictionary alloc] init];
		historyPosition = NSNotFound;
		modifyingHistoryState = NO;
	}
	return self;	
}

- (void) awakeFromNib
{
	tableContentInstance = [theDocument valueForKey:@"tableContentInstance"];
	tablesListInstance = [theDocument valueForKey:@"tablesListInstance"];
}

- (void) dealloc
{
	[tableContentStates release];
	[history release];
	[super dealloc];
}

#pragma mark -
#pragma mark Interface interaction

/**
 * Updates the toolbar item to reflect the current history state and position
 */
- (void) updateToolbarItem
{
	BOOL backEnabled = NO;
	BOOL forwardEnabled = NO;
	NSInteger i;
	NSMenu *navMenu;

	// Set the active state of the segments if appropriate
	if ([history count] && historyPosition > 0) backEnabled = YES;
	if ([history count] && historyPosition + 1 < [history count]) forwardEnabled = YES;
	
	[historyControl setEnabled:backEnabled forSegment:0];
	[historyControl setEnabled:forwardEnabled forSegment:1];

	// Generate back and forward menus as appropriate to reflect the new state
	if (backEnabled) {
		navMenu = [[NSMenu alloc] init];
		for (i = historyPosition - 1; i >= 0; i--) {
			[navMenu addItem:[self menuEntryForHistoryEntryAtIndex:i]];
		}
		[historyControl setMenu:navMenu forSegment:0];
		[navMenu release];
	} else {
		[historyControl setMenu:nil forSegment:0];
	}
	if (forwardEnabled) {
		navMenu = [[NSMenu alloc] init];
		for (i = historyPosition + 1; i < [history count]; i++) {
			[navMenu addItem:[self menuEntryForHistoryEntryAtIndex:i]];
		}
		[historyControl setMenu:navMenu forSegment:1];
		[navMenu release];
	} else {
		[historyControl setMenu:nil forSegment:1];
	}
}

/**
 * Go backward in the history.
 */
- (void)goBackInHistory
{
	if (historyPosition == NSNotFound || !historyPosition) return;
	
	[self loadEntryAtPosition:historyPosition - 1];
}

/**
 * Go forward in the history.
 */
- (void)goForwardInHistory
{
	if (historyPosition == NSNotFound || historyPosition + 1 >= [history count]) return;
	
	[self loadEntryAtPosition:historyPosition + 1];
}

/**
 * Trigger a navigation action in response to a click
 */
- (IBAction) historyControlClicked:(NSSegmentedControl *)theControl
{

	switch ([theControl selectedSegment]) 
	{
		// Back button clicked:
		case 0:
			[self goBackInHistory];
			break;

		// Forward button clicked:
		case 1:
			[self goForwardInHistory];
			break;
	}
}

/**
 * Retrieve the view that is currently selected from the database
 */
- (NSUInteger) currentlySelectedView
{
	NSUInteger theView = NSNotFound;

	NSString *viewName = [[[theDocument valueForKey:@"tableTabView"] selectedTabViewItem] identifier];
	if ([viewName isEqualToString:@"source"]) {
		theView = SP_VIEW_STRUCTURE;
	} else if ([viewName isEqualToString:@"content"]) {
		theView = SP_VIEW_CONTENT;
	} else if ([viewName isEqualToString:@"customQuery"]) {
		theView = SP_VIEW_CUSTOMQUERY;
	} else if ([viewName isEqualToString:@"status"]) {
		theView = SP_VIEW_STATUS;
	} else if ([viewName isEqualToString:@"relations"]) {
		theView = SP_VIEW_RELATIONS;
	}

	return theView;
}

#pragma mark -
#pragma mark Adding or updating history entries

/**
 * Call to store or update a history item for the document state. Checks against
 * the latest stored details; if they match, a new history item is not created.
 * This should therefore be called without worry of duplicates.
 * Table histories are created per table/filter setting, and while view changes
 * update the current history entry, they don't replace it.
 */
- (void) updateHistoryEntries
{

	// Don't modify anything if we're in the process of restoring an old history state
	if (modifyingHistoryState) return;

	// Work out the current document details
	NSString *theDatabase = [theDocument database];
	NSString *theTable = [theDocument table];
	NSUInteger theView = [self currentlySelectedView];
	NSString *contentSortCol = [tableContentInstance sortColumnName];
	BOOL contentSortColIsAsc = [tableContentInstance sortColumnIsAscending];
	NSUInteger contentPageNumber = [tableContentInstance pageNumber];
	NSIndexSet *contentSelectedIndexSet = [tableContentInstance selectedRowIndexes];
	NSRect contentViewport = [tableContentInstance viewport];
	NSDictionary *contentFilter = [tableContentInstance filterSettings];
	if (!theDatabase) return;

	// If a table is selected, save state information
	if (theDatabase && theTable) {

		// Save the table content state
		NSMutableDictionary *contentState = [NSMutableDictionary dictionaryWithObjectsAndKeys:
												[NSNumber numberWithUnsignedInteger:contentPageNumber], @"page",
												[NSValue valueWithRect:contentViewport], @"viewport",
												[NSNumber numberWithBool:contentSortColIsAsc], @"sortIsAsc",
												nil];
		if (contentSortCol) [contentState setObject:contentSortCol forKey:@"sortCol"];
		if (contentSelectedIndexSet) [contentState setObject:contentSelectedIndexSet forKey:@"selection"];
		if (contentFilter) [contentState setObject:contentFilter forKey:@"filter"];
		[tableContentStates setObject:contentState forKey:[NSString stringWithFormat:@"%@.%@", [theDatabase backtickQuotedString], [theTable backtickQuotedString]]];
	}

	// If there's any items after the current history position, remove them
	if (historyPosition != NSNotFound && historyPosition < [history count] - 1) {
		[history removeObjectsInRange:NSMakeRange(historyPosition + 1, [history count] - historyPosition - 1)];

	} else if (historyPosition != NSNotFound && historyPosition == [history count] - 1) {
		NSDictionary *currentHistoryEntry = [history objectAtIndex:historyPosition];

		// If the table is the same, and the filter settings haven't changed, delete the
		// last entry so it can be replaced.  This updates navigation within a table, rather than
		// creating a new entry every time detail is changed.
		if ([[currentHistoryEntry objectForKey:@"database"] isEqualToString:theDatabase]
			&& [[currentHistoryEntry objectForKey:@"table"] isEqualToString:theTable]
			&& ([[currentHistoryEntry objectForKey:@"view"] integerValue] != theView
				|| ((![currentHistoryEntry objectForKey:@"contentFilter"] && !contentFilter)
					|| (![currentHistoryEntry objectForKey:@"contentFilter"]
						&& ![(NSString *)[contentFilter objectForKey:@"filterValue"] length]
						&& ![[contentFilter objectForKey:@"filterComparison"] isEqualToString:@"IS NULL"]
						&& ![[contentFilter objectForKey:@"filterComparison"] isEqualToString:@"IS NOT NULL"])
					|| [[currentHistoryEntry objectForKey:@"contentFilter"] isEqualToDictionary:contentFilter])))
		{
			[history removeLastObject];

		// Special case: if the last history item is currently active, and has no table,
		// but the new selection does - delete the last entry, in order to replace it.
		// This improves history flow.
		} else if ([[currentHistoryEntry objectForKey:@"database"] isEqualToString:theDatabase]
			&& ![currentHistoryEntry objectForKey:@"table"])
		{
			[history removeLastObject];
		}
	}

	// Construct and add the new history entry
	NSMutableDictionary *newEntry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
										theDatabase, @"database",
										theTable, @"table",
										[NSNumber numberWithInteger:theView], @"view",
										[NSNumber numberWithBool:contentSortColIsAsc], @"contentSortColIsAsc",
										[NSNumber numberWithInteger:contentPageNumber], @"contentPageNumber",
										[NSValue valueWithRect:contentViewport], @"contentViewport",
										nil];
	if (contentSortCol) [newEntry setObject:contentSortCol forKey:@"contentSortCol"];
	if (contentSelectedIndexSet) [newEntry setObject:contentSelectedIndexSet forKey:@"contentSelectedIndexSet"];
	if (contentFilter) [newEntry setObject:contentFilter forKey:@"contentFilter"];

	[history addObject:newEntry];
	
	// If there are now more than fifty history entries, remove one from the start
	if ([history count] > 50) [history removeObjectAtIndex:0];

	historyPosition = [history count] - 1;
	[self updateToolbarItem];
}

#pragma mark -
#pragma mark Loading history entries

/**
 * Load a history entry and attempt to return the interface to that state.
 * Performs the load in a task which is threaded as necessary.
 */
- (void) loadEntryAtPosition:(NSUInteger)position
{

	// Sanity check the input
	if (position == NSNotFound || position < 0 || position >= [history count]) {
		NSBeep();
		return;
	}

	// Ensure a save of the current state - scroll position, selection - if we're at the last entry
	if (historyPosition == [history count] - 1) [self updateHistoryEntries];

	// Start the task and perform the load
	[theDocument startTaskWithDescription:NSLocalizedString(@"Loading history entry...", @"Loading history entry task desc")];
	if ([NSThread isMainThread]) {
		[NSThread detachNewThreadSelector:@selector(loadEntryTaskWithPosition:) toTarget:self withObject:[NSNumber numberWithUnsignedInteger:position]];
	} else {
		[self loadEntryTaskWithPosition:[NSNumber numberWithUnsignedInteger:position]];
	}
}
- (void) loadEntryTaskWithPosition:(NSNumber *)positionNumber
{
	NSAutoreleasePool *loadPool = [[NSAutoreleasePool alloc] init];
	NSUInteger position = [positionNumber unsignedIntegerValue];

	modifyingHistoryState = YES;

	// Update the position and extract the history entry
	historyPosition = position;
	NSDictionary *historyEntry = [history objectAtIndex:historyPosition];

	// Set table content details for restore
	[tableContentInstance setSortColumnNameToRestore:[historyEntry objectForKey:@"contentSortCol"] isAscending:[[historyEntry objectForKey:@"contentSortColIsAsc"] boolValue]];
	[tableContentInstance setPageToRestore:[[historyEntry objectForKey:@"contentPageNumber"] integerValue]];
	[tableContentInstance setSelectedRowIndexesToRestore:[historyEntry objectForKey:@"contentSelectedIndexSet"]];
	[tableContentInstance setViewportToRestore:[[historyEntry objectForKey:@"contentViewport"] rectValue]];
	[tableContentInstance setFiltersToRestore:[historyEntry objectForKey:@"contentFilter"]];

	// If the database, table, and view are the same and content - just trigger a table reload (filters)
	if ([[theDocument database] isEqualToString:[historyEntry objectForKey:@"database"]]
		&& [historyEntry objectForKey:@"table"] && [[theDocument table] isEqualToString:[historyEntry objectForKey:@"table"]]
		&& [[historyEntry objectForKey:@"view"] integerValue] == [self currentlySelectedView] == SP_VIEW_CONTENT)
	{
		[tableContentInstance loadTable:[historyEntry objectForKey:@"table"]];
		modifyingHistoryState = NO;
		[self updateToolbarItem];
		[theDocument endTask];
		[loadPool drain];
		return;
	}

	// Check and set the database
	if (![[theDocument database] isEqualToString:[historyEntry objectForKey:@"database"]]) {
		NSPopUpButton *chooseDatabaseButton = [theDocument valueForKey:@"chooseDatabaseButton"];
		[tablesListInstance setTableListSelectability:YES];
		[[tablesListInstance valueForKey:@"tablesListView"] deselectAll:self];		
		[theDocument setDatabaseListIsSelectable:YES];
		[tablesListInstance setTableListSelectability:YES];
		[chooseDatabaseButton selectItemWithTitle:[historyEntry objectForKey:@"database"]];
		[theDocument chooseDatabase:self];
		if (![[theDocument database] isEqualToString:[historyEntry objectForKey:@"database"]]) {
			return [self abortEntryLoadWithPool:loadPool];
		}
	}

	// Check and set the table
	if ([historyEntry objectForKey:@"table"] && ![[theDocument table] isEqualToString:[historyEntry objectForKey:@"table"]]) {
		NSArray *tables = [tablesListInstance tables];
		if ([tables indexOfObject:[historyEntry objectForKey:@"table"]] == NSNotFound) {
			return [self abortEntryLoadWithPool:loadPool];
		}
		[[tablesListInstance valueForKey:@"tablesListView"] selectRowIndexes:[NSIndexSet indexSetWithIndex:[tables indexOfObject:[historyEntry objectForKey:@"table"]]] byExtendingSelection:NO];
		if (![[theDocument table] isEqualToString:[historyEntry objectForKey:@"table"]]) {
			return [self abortEntryLoadWithPool:loadPool];
		}
	} else if (![historyEntry objectForKey:@"table"] && [theDocument table]) {
		[tablesListInstance setTableListSelectability:YES];
		[[tablesListInstance valueForKey:@"tablesListView"] deselectAll:self];		
	} else {
		[tablesListInstance setContentRequiresReload:YES];	
	}

	// Check and set the view
	if ([self currentlySelectedView] != [[historyEntry objectForKey:@"view"] integerValue]) {
		switch ([[historyEntry objectForKey:@"view"] integerValue]) {
			case SP_VIEW_STRUCTURE:
				[theDocument viewStructure:self];
				break;
			case SP_VIEW_CONTENT:
				[theDocument viewContent:self];
				break;
			case SP_VIEW_CUSTOMQUERY:
				[theDocument viewQuery:self];
				break;
			case SP_VIEW_STATUS:
				[theDocument viewStatus:self];
				break;
			case SP_VIEW_RELATIONS:
				[theDocument viewRelations:self];
				break;
		}
		if ([self currentlySelectedView] != [[historyEntry objectForKey:@"view"] integerValue]) {
			return [self abortEntryLoadWithPool:loadPool];
		}
	}

	modifyingHistoryState = NO;
	[self updateToolbarItem];

	// End the task
	[theDocument endTask];
	[loadPool drain];
}

/**
 * Convenience method for aborting history load - could at some point
 * clean up the history list, show an alert, etc
 */
- (void) abortEntryLoadWithPool:(NSAutoreleasePool *)pool
{
	NSBeep();
	modifyingHistoryState = NO;
	[theDocument endTask];
	if (pool) [pool drain];
}

/**
 * Load a history entry from an associated menu item
 */
- (void) loadEntryFromMenuItem:(id)theMenuItem
{
	[self loadEntryAtPosition:[theMenuItem tag]];
}

#pragma mark -
#pragma mark Restoring view states

/**
 * Check saved view states for the currently selected database and
 * table (if any), and restore them if present.
 */
- (void) restoreViewStates
{
	NSString *theDatabase = [theDocument database];
	NSString *theTable = [theDocument table];
	NSDictionary *contentState;

	// Return if the history state is currently being modified
	if (modifyingHistoryState) return;

	// Return if no database or table are selected
	if (!theDatabase || !theTable) return;

	// Retrieve the saved content state, returning if none was found
	contentState = [tableContentStates objectForKey:[NSString stringWithFormat:@"%@.%@", [theDatabase backtickQuotedString], [theTable backtickQuotedString]]];
	if (!contentState) return;

	// Restore the content view state
	[tableContentInstance setSortColumnNameToRestore:[contentState objectForKey:@"sortCol"] isAscending:[[contentState objectForKey:@"sortIsAsc"] boolValue]];
	[tableContentInstance setPageToRestore:[[contentState objectForKey:@"page"] unsignedIntegerValue]];
	[tableContentInstance setSelectedRowIndexesToRestore:[contentState objectForKey:@"selection"]];
	[tableContentInstance setViewportToRestore:[[contentState objectForKey:@"viewport"] rectValue]];
	[tableContentInstance setFiltersToRestore:[contentState objectForKey:@"filter"]];
}

#pragma mark -
#pragma mark History entry details and description

/**
 * Returns a menuitem for a history entry at a supplied index
 */
- (NSMenuItem *) menuEntryForHistoryEntryAtIndex:(NSInteger)theIndex
{
	NSMenuItem *theMenuItem = [[NSMenuItem alloc] init];
	NSDictionary *theHistoryEntry = [history objectAtIndex:theIndex];

	[theMenuItem setTag:theIndex];
	[theMenuItem setTitle:[self nameForHistoryEntryDetails:theHistoryEntry]];
	[theMenuItem setTarget:self];
	[theMenuItem setAction:@selector(loadEntryFromMenuItem:)];
	
	return [theMenuItem autorelease];
}

/**
 * Returns a descriptive name for a history item dictionary
 */
- (NSString *) nameForHistoryEntryDetails:(NSDictionary *)theEntry
{
	if (![theEntry objectForKey:@"database"]) return NSLocalizedString(@"(no selection)", @"History item title with nothing selected");

	NSMutableString *theName = [NSMutableString stringWithString:[theEntry objectForKey:@"database"]];
	if (![theEntry objectForKey:@"table"] || ![(NSString *)[theEntry objectForKey:@"table"] length]) return theName;

	[theName appendFormat:@"/%@", [theEntry objectForKey:@"table"]];

	if ([theEntry objectForKey:@"contentFilter"]) {
		NSDictionary *filterSettings = [theEntry objectForKey:@"contentFilter"];
		if ([filterSettings objectForKey:@"filterField"]) {
			if([filterSettings objectForKey:@"menuLabel"]) {
				theName = [NSString stringWithFormat:NSLocalizedString(@"%@ (Filtered by %@)", @"History item filtered by values label"), 
							theName, [filterSettings objectForKey:@"menuLabel"]];
			}
		}
	}

	if ([theEntry objectForKey:@"contentPageNumber"]) {
		NSUInteger pageNumber = [[theEntry objectForKey:@"contentPageNumber"] unsignedIntegerValue];
		if (pageNumber > 1) {
			theName = [NSString stringWithFormat:NSLocalizedString(@"%@ (Page %lu)", @"History item with page number label"),
						theName, (unsigned long)pageNumber];
		}
	}

	return theName;
}

@end