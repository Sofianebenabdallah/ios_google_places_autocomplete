//
//  GooglePlacesAutocomplete.swift
//  GooglePlacesAutocomplete
//
//  Created by Howard Wilson on 10/02/2015.
//  Copyright (c) 2015 Howard Wilson. All rights reserved.
//

import UIKit
import CoreLocation

public let ErrorDomain: String! = "GooglePlacesAutocompleteErrorDomain"

public struct LocationBias {
  public let latitude: CLLocationDegrees
  public let longitude: CLLocationDegrees
  public let radius: CLLocationDistance
  
  public init(latitude: Double = 0, longitude: Double = 0, radius: CLLocationDistance = 20000000) {
    self.latitude = latitude
    self.longitude = longitude
    self.radius = radius
  }

  public init(location:CLLocation, radius: CLLocationDistance = 20000000){
    self.latitude = location.coordinate.latitude
    self.longitude = location.coordinate.longitude
    self.radius = radius
  }

  public init(region:CLCircularRegion){
    self.latitude = region.center.latitude
    self.longitude = region.center.longitude
    self.radius = region.radius
  }

  public var location: String {
    return "\(latitude),\(longitude)"
  }
}

public enum PlaceType: CustomStringConvertible {
  case All
  case Geocode
  case Address
  case Establishment
  case Regions
  case Cities

  public var description : String {
    switch self {
      case .All: return ""
      case .Geocode: return "geocode"
      case .Address: return "address"
      case .Establishment: return "establishment"
      case .Regions: return "(regions)"
      case .Cities: return "(cities)"
    }
  }
}

public class Place: NSObject {
  public let id: String
  public let desc: String
  public var apiKey: String?

  override public var description: String {
    get { return desc }
  }

  public init(id: String, description: String) {
    self.id = id
    self.desc = description
  }

  public convenience init(prediction: [String: AnyObject], apiKey: String?) {
    self.init(
      id: prediction["place_id"] as! String,
      description: prediction["description"] as! String
    )

    self.apiKey = apiKey
  }

  /**
    Call Google Place Details API to get detailed information for this place
  
    Requires that Place#apiKey be set
  
    - parameter result: Callback on successful completion with detailed place information
  */
  public func getDetails(result: PlaceDetails -> ()) {
    GooglePlaceDetailsRequest(place: self).request(result)
  }
}

public class PlaceDetails: CustomStringConvertible {
  public let name: String
  public let latitude: Double
  public let longitude: Double
    
    public let location: CLLocation
    
    public var region: CLCircularRegion
    
    public var radius: CLLocationDistance {
        get {
            return region.radius
        }
    }
    
  public let raw: [String: AnyObject]

  public init(json: [String: AnyObject]) {
    let result = json["result"] as! [String: AnyObject]
    let geometry = result["geometry"] as! [String: AnyObject]
    let location = geometry["location"] as! [String: AnyObject]

    self.name = result["name"] as! String
    self.latitude = location["lat"] as! Double
    self.longitude = location["lng"] as! Double
    self.location = CLLocation(latitude: self.latitude, longitude: self.longitude)!
    
    var radius: CLLocationDistance = 0
    
    if let viewport = geometry["viewport"] as? [String: AnyObject] {
        let northEastDict = viewport["northeast"] as! [String: AnyObject]
        let northEast = CLLocation(latitude: northEastDict["lat"] as! Double, longitude: northEastDict["lng"] as! Double)
        let southWestDict = viewport["southwest"] as! [String: AnyObject]
        let southWest = CLLocation(latitude: southWestDict["lat"] as! Double, longitude: southWestDict["lng"] as! Double)
        
        
        radius = self.location.distanceFromLocation(northEast!)
    }
    
    
    self.region = CLCircularRegion(center: self.location.coordinate, radius: radius, identifier: self.name)!
    
    
    self.raw = json
    
  }

  public var description: String {
    return "PlaceDetails: \(name) (\(latitude), \(longitude))"
  }
}

@objc public protocol GooglePlacesAutocompleteDelegate {
  optional func placesFound(places: [Place])
  optional func placeSelected(place: Place)
  optional func placeViewClosed()
}

// MARK: - GooglePlacesAutocompleteService

public class GooglePlacesAutocompleteService {
  var delegate: GooglePlacesAutocompleteDelegate?
  var apiKey: String?
  var places = [Place]()
  public var placeType: PlaceType = .All
  public var locationBias: LocationBias?
  public var country: String?
  
  public init(apiKey: String, placeType: PlaceType = .All) {
    self.apiKey = apiKey
    self.placeType = placeType
  }
  
  public func getPlaces(searchString: String, completion:(([Place]?, NSError?) -> Void)) {
    var params = [
      "input": searchString,
      "types": placeType.description,
      "key": apiKey ?? ""
    ]
    
    if let bias = locationBias {
      params["location"] = bias.location
      params["radius"] = bias.radius.description
    }
    
    if let country = country {
        params["components"] = "country:\(country)"
    }
    
    if (searchString == ""){
        let error = NSError(domain: ErrorDomain, code: 1000, userInfo: [NSLocalizedDescriptionKey:"No search string given"])
        completion(nil,error)
        return
    }
    
    GooglePlacesRequestHelpers.doRequest(
      "https://maps.googleapis.com/maps/api/place/autocomplete/json",
      params: params
      ) { json, error in
        if let json = json{
            if let predictions = json["predictions"] as? Array<[String: AnyObject]> {
              self.places = predictions.map { (prediction: [String: AnyObject]) -> Place in
                return Place(prediction: prediction, apiKey: self.apiKey)
              }
              self.delegate?.placesFound?(self.places)
              completion(self.places, error)

            } else {
                completion(nil, error)
            }
        } else {
            completion(nil,error)
        }
    }
  }
}

// MARK: - GooglePlacesAutocomplete (UINavigationController)

public class GooglePlacesAutocomplete: UINavigationController {
  public var gpaViewController: GooglePlacesAutocompleteContainer!
  public var closeButton: UIBarButtonItem!
  
  public var gpaService: GooglePlacesAutocompleteService!

  // Proxy access to container navigationItem
  public override var navigationItem: UINavigationItem {
    get { return gpaViewController.navigationItem }
  }

  public var placeDelegate: GooglePlacesAutocompleteDelegate? {
    get { return gpaService.delegate }
    set { gpaService.delegate = newValue }
  }
  
  public var locationBias: LocationBias? {
    get { return gpaService.locationBias }
    set { gpaService.locationBias = newValue }
  }

  public convenience init(apiKey: String, placeType: PlaceType = .All) {
    let service = GooglePlacesAutocompleteService(apiKey: apiKey, placeType: placeType)
    self.init(service:service)
  }
  
  public convenience init(service: GooglePlacesAutocompleteService) {

    let gpaViewController = GooglePlacesAutocompleteContainer(service: service)
    self.init(rootViewController: gpaViewController)
    self.gpaService = service
    self.gpaViewController = gpaViewController
    
    closeButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Stop, target: self, action: "close")
    closeButton.style = UIBarButtonItemStyle.Done

    gpaViewController.navigationItem.leftBarButtonItem = closeButton
    gpaViewController.navigationItem.title = "Enter Address"
  }

  func close() {
    placeDelegate?.placeViewClosed?()
  }

  public func reset() {
    gpaViewController.searchBar.text = ""
    gpaViewController.searchBar(gpaViewController.searchBar, textDidChange: "")
  }
}

// MARK: - GooglePlacesAutocompleteContainer
public class GooglePlacesAutocompleteContainer: UIViewController {
  @IBOutlet public weak var searchBar: UISearchBar!
  @IBOutlet weak var tableView: UITableView!
  @IBOutlet weak var topConstraint: NSLayoutConstraint!

  public var gpaService: GooglePlacesAutocompleteService!

  convenience init(service: GooglePlacesAutocompleteService) {
    let bundle = NSBundle(forClass: GooglePlacesAutocompleteContainer.self)

    self.init(nibName: "GooglePlacesAutocomplete", bundle: bundle)
    self.gpaService = service
  }

  deinit {
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }

  override public func viewWillLayoutSubviews() {
    topConstraint.constant = topLayoutGuide.length
  }

  override public func viewDidLoad() {
    super.viewDidLoad()

    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWasShown:", name: UIKeyboardDidShowNotification, object: nil)
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillBeHidden:", name: UIKeyboardWillHideNotification, object: nil)

    searchBar.becomeFirstResponder()
    tableView.registerClass(UITableViewCell.self, forCellReuseIdentifier: "Cell")
  }

  func keyboardWasShown(notification: NSNotification) {
    if isViewLoaded() && view.window != nil {
      let info: Dictionary = notification.userInfo!
      let keyboardSize: CGSize = (info[UIKeyboardFrameBeginUserInfoKey]?.CGRectValue.size)!
      let contentInsets = UIEdgeInsetsMake(0.0, 0.0, keyboardSize.height, 0.0)

      tableView.contentInset = contentInsets;
      tableView.scrollIndicatorInsets = contentInsets;
    }
  }

  func keyboardWillBeHidden(notification: NSNotification) {
    if isViewLoaded() && view.window != nil {
      self.tableView.contentInset = UIEdgeInsetsZero
      self.tableView.scrollIndicatorInsets = UIEdgeInsetsZero
    }
  }
}

// MARK: - GooglePlacesAutocompleteContainer (UITableViewDataSource / UITableViewDelegate)
extension GooglePlacesAutocompleteContainer: UITableViewDataSource, UITableViewDelegate {
  public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return gpaService.places.count
  }

  public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) 

    // Get the corresponding candy from our candies array
    let place = gpaService.places[indexPath.row]

    // Configure the cell
    cell.textLabel!.text = place.description
    cell.accessoryType = UITableViewCellAccessoryType.DisclosureIndicator
    
    return cell
  }

  public func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    gpaService.delegate?.placeSelected?(gpaService.places[indexPath.row])
  }
}

// MARK: - GooglePlacesAutocompleteContainer (UISearchBarDelegate)
extension GooglePlacesAutocompleteContainer: UISearchBarDelegate {
  public func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {
    if (searchText == "") {
      gpaService.places = []
      tableView.hidden = true
    } else {
      getPlaces(searchText)
    }
  }

  /**
    Call the Google Places API and update the view with results.

    - parameter searchString: The search query
  */
  
  func getPlaces(searchText: String){
    gpaService.getPlaces(searchText, completion: {(places: [Place]?,error: NSError?) in
      self.tableView.reloadData()
      self.tableView.hidden = false

      }
    )
  }
}

// MARK: - GooglePlaceDetailsRequest
class GooglePlaceDetailsRequest {
  let place: Place

  init(place: Place) {
    self.place = place
  }

  func request(result: PlaceDetails -> ()) {
    GooglePlacesRequestHelpers.doRequest(
      "https://maps.googleapis.com/maps/api/place/details/json",
      params: [
        "placeid": place.id,
        "key": place.apiKey ?? ""
      ]
    ) { json, error in
      if let json = json as? [String: AnyObject] {
        result(PlaceDetails(json: json))
      }
      if let error = error {
        // TODO: We should probably pass back details of the error
        print("Error fetching google place details: \(error)")
      }
    }
  }
}

// MARK: - GooglePlacesRequestHelpers
class GooglePlacesRequestHelpers {
  /**
  Build a query string from a dictionary

  - parameter parameters: Dictionary of query string parameters
  - returns: The properly escaped query string
  */
  private class func query(parameters: [String: AnyObject]) -> String {
    var components: [(String, String)] = []
    for key in Array(parameters.keys).sort(<) {
      let value: AnyObject! = parameters[key]
      components += [(escape(key), escape("\(value)"))]
    }

    return (components.map{"\($0)=\($1)"} as [String]).joinWithSeparator("&")
  }

  private class func escape(string: String) -> String {
    let legalURLCharactersToBeEscaped: CFStringRef = ":/?&=;+!@#$()',*"
    return CFURLCreateStringByAddingPercentEscapes(nil, string, nil, legalURLCharactersToBeEscaped, CFStringBuiltInEncodings.UTF8.rawValue) as String
  }

  private class func doRequest(url: String, params: [String: String], completion: (NSDictionary?,NSError?) -> ()) {
    let request = NSMutableURLRequest(
      URL: NSURL(string: "\(url)?\(query(params))")!
    )

    let session = NSURLSession.sharedSession()
    let task = session.dataTaskWithRequest(request) { data, response, error in
      self.handleResponse(data, response: response as? NSHTTPURLResponse, error: error, completion: completion)
    }

    task.resume()
  }

  private class func handleResponse(data: NSData!, response: NSHTTPURLResponse!, error: NSError!, completion: (NSDictionary?, NSError?) -> ()) {
    
    // Always return on the main thread...
    let done: ((NSDictionary?, NSError?) -> Void) = {(json, error) in
        dispatch_async(dispatch_get_main_queue(), {
            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
            completion(json,error)
        })
    }
    
    if let error = error {
      print("GooglePlaces Error: \(error.localizedDescription)")
      done(nil,error)
      return
    }

    if response == nil {
      print("GooglePlaces Error: No response from API")
      let error = NSError(domain: ErrorDomain, code: 1001, userInfo: [NSLocalizedDescriptionKey:"No response from API"])
      done(nil,error)
      return
    }

    if response.statusCode != 200 {
      print("GooglePlaces Error: Invalid status code \(response.statusCode) from API")
      let error = NSError(domain: ErrorDomain, code: response.statusCode, userInfo: [NSLocalizedDescriptionKey:"Invalid status code"])
      done(nil,error)
      return
    }
    
    let json: NSDictionary?
    do {
      json = try NSJSONSerialization.JSONObjectWithData(
        data,
        options: NSJSONReadingOptions.MutableContainers) as? NSDictionary
    } catch {
      print("Serialisation error")

      let serialisationError = NSError(domain: ErrorDomain, code: 1002, userInfo: [NSLocalizedDescriptionKey:"Serialization error"])
      done(nil,serialisationError)
      return
    }

    if let status = json?["status"] as? String {
      if status != "OK" {
        print("GooglePlaces API Error: \(status)")
        let error = NSError(domain: ErrorDomain, code: 1002, userInfo: [NSLocalizedDescriptionKey:status])
        done(nil,error)
        return
      }
    }
    
    done(json,nil)

  }
}
