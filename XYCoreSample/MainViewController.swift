//
//  ViewController.swift
//  XYCoreSample
//
//  Created by Arie Trouw on 5/16/17.
//  Copyright © 2017 XY - The Findables Company. All rights reserved.
//

import UIKit
import XYCore

class MainViewController: UIViewController {

    @IBOutlet weak var txtFirebaseStatus: UITextField!
    @IBOutlet weak var txtFabricStatus: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        txtFabricStatus.text = "Hello"
        txtFirebaseStatus.text = "There"
    }

    @IBAction func testLoggingPressed(_ sender: Any) {
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

