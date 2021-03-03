//
//  logTableviewController.swift
//  DSS-APP
//
//  Created by Andreas Gising on 2021-03-03.
//  Copyright © 2021 DJI. All rights reserved.
//

import Foundation
import UIKit

class TableViewController: UITableViewController{
    
    var dataSource: [String] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Add observer that will fetch the log data
        NotificationCenter.default.addObserver(self, selector: #selector(onDidNewLogItem(_:)), name: .didNewLogItem, object: nil)
    }
    
    // *****************************************
    // Function to scroll to bottom of tableView
    func scrollToBottom(){
        DispatchQueue.main.async {
            let indexPath = IndexPath(row: self.dataSource.count-1, section: 0)
            self.tableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        }
    }
    
    // *************************************************
    // Function called upon receiving a log notification
    @objc func onDidNewLogItem(_ notification: Notification){
        let logStr = String(describing: notification.userInfo!["logItem"]!)
        // Limit log to 100 instances
        if dataSource.count > 100 {
            dataSource.remove(at: 0)
            // Remove one more to maintain the visible effect of scrolling when new entries appear
            dataSource.remove(at: 0)
        }
        // Append log str to datasource
        dataSource.append(logStr)
        // Reload and wait a bit to be sure scroll to bottom does not exceed any bounds
        Dispatch.main{
            self.tableView.reloadData()
        }
        usleep(1000)
        scrollToBottom()
    }
   
    
    // ********************************************
    // Dynamically set number of cells in tableView
    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let rows = dataSource.count
        return rows
    }
    
    // ***********************
    // Allocaiton of new cells
    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let customCell = tableView.dequeueReusableCell(withIdentifier: "logCell") as! logTableViewCell
        
        // Put the log str in the cell label
        customCell.cellLabel.text = dataSource[indexPath.row]
        customCell.cellLabel.textColor = UIColor.black
        
        // Look for Error and set background to red if so
        if customCell.cellLabel.text!.contains("Error") || customCell.cellLabel.text!.contains("violation"){
            customCell.backgroundColor = UIColor.systemRed
        }
        else{
            customCell.backgroundColor = UIColor.systemGray
        }
        return customCell
    }
}


// Class for tableViewCell
class logTableViewCell: UITableViewCell{
    @IBOutlet weak var cellLabel: UILabel!
}
