//
//  ViewController.swift
//  GooglePlacesAutocompleteExample
//
//  Created by Howard Wilson on 15/02/2015.
//  Copyright (c) 2015 Howard Wilson. All rights reserved.
//

import UIKit
import GooglePlacesAutocomplete


#if API_KEY
  /// You can either set an API_KEY environment variable which will be used by the example and tests ...
  lazy var apiKey: String = {
    let dict = NSProcessInfo.processInfo().environment
    return dict["API_KEY"] as! String
  }()
#else
  /// or you can type one in here - just try not to reveal it to the world
  let apiKey: String = "API_KEY"
#endif
  
  
class ViewController: UIViewController {
  let gpaViewController = GooglePlacesAutocomplete(
    apiKey: apiKey,
    placeType: .address
  )

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    gpaViewController.placeDelegate = self

    present(gpaViewController, animated: true, completion: nil)
  }
}

extension ViewController: GooglePlacesAutocompleteDelegate {
  func placeSelected(_ place: Place) {
    print(place.description)

    place.getDetails { details in
      print(details)
    }
  }

  func placeViewClosed() {
    dismiss(animated: true, completion: nil)
  }
}
