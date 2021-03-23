//
//  ZBSourceListViewController.m
//  Zebra
//
//  Created by Wilson Styres on 1/1/21.
//  Copyright © 2021 Wilson Styres. All rights reserved.
//

#import "ZBSourceListViewController.h"

#import <UI/Sources/Views/Cells/ZBSourceTableViewCell.h>
#import <UI/Sources/ZBSourceViewController.h>

#import <Plains/PLDatabase.h>
#import <Plains/PLSource.h>

@import SDWebImage;

@interface ZBSourceListViewController () {
    PLDatabase *database;
    NSArray *sources;
}
@end

@implementation ZBSourceListViewController

- (id)init {
    self = [super initWithStyle:UITableViewStylePlain];
    
    if (self) {
        self.title = @"Sources";
        
        database = [PLDatabase sharedInstance];
    }
    
    return self;
} 

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self action:@selector(refreshSources) forControlEvents:UIControlEventValueChanged];
    
    [self.tableView setTableHeaderView:[[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 1)]];
    [self.tableView setTableFooterView:[[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 1)]];
    [self.tableView registerNib:[UINib nibWithNibName:@"ZBSourceTableViewCell" bundle:nil] forCellReuseIdentifier:@"sourceTableViewCell"];
    
    [self loadSources];
}

- (void)loadSources {
    if (!self.isViewLoaded) return;
    
    if (sources) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIView transitionWithView:self.tableView duration:0.20f options:UIViewAnimationOptionTransitionCrossDissolve animations:^(void) {
                [self.tableView reloadData];
            } completion:nil];
        });
    } else { // Load sources for the first time, every other access is done by the filter and delegate methods
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            self->sources = [[self->database sources] sortedArrayUsingSelector:@selector(compareByOrigin:)];
            [self loadSources];
        });
    }
}

- (void)refreshSources {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [database refreshSources];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.refreshControl endRefreshing];
        });
    });
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return sources.count;
}

- (ZBSourceTableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    ZBSourceTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sourceTableViewCell" forIndexPath:indexPath];
    
    PLSource *source = sources[indexPath.row];
    cell.sourceLabel.text = source.origin;
    cell.urlLabel.text = source.URI.absoluteString;
    [cell.iconImageView sd_setImageWithURL:[source iconURL]];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    ZBSourceViewController *sourceController = [[ZBSourceViewController alloc] initWithSource:sources[indexPath.row]];
    [[self navigationController] pushViewController:sourceController animated:YES];
}

@end
