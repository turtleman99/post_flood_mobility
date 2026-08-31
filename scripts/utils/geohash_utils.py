import geohash
from shapely.geometry import Polygon

def geohash_to_polygon(ghash):
    # Decode geohash to get the bounding box
    bbox = geohash.bbox(ghash)
    
    # Extract the bounding box corners
    south, west = bbox['s'], bbox['w']
    north, east = bbox['n'], bbox['e']
    
    # Create a polygon from the bounding box
    polygon = Polygon([(west, south), (west, north), (east, north), (east, south)])
    
    return polygon