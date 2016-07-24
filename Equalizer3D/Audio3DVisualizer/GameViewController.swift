//
//  GameViewController.swift
//  Audio3DVisualizer
//
//  Created by Jonathan Ritchey on 7/23/16.
//  Copyright (c) 2016 Jonathan Ritchey. All rights reserved.
//

import UIKit
import QuartzCore
import SceneKit

extension UIColor {
    var components:(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r,g,b,a)
    }
}

class GameViewController: UIViewController {

    var scnView: SCNView!
    var scnScene: SCNScene!
    var cameraNode: SCNNode!
    var grid: [SCNNode] = []
    
    var colorByBand: [UIColor] = []
    var colorByBandRed: [CGFloat] = []
    var colorByBandGreen: [CGFloat] = []
    var colorByBandBlue: [CGFloat] = []
    
    var superpowered:Superpowered!
    var displayLink:CADisplayLink!
    var layers:[CALayer] = []

    enum VisualizationType {
        case Rectangle
        case Spiral
    }
    
    var visualizationType = VisualizationType.Spiral
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupAudio()
        setupView()
        setupScene()
        setupCamera()
        setupGrid()
        setupColorGrid()
    }
    
    override func shouldAutorotate() -> Bool {
        return true
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    
    func setupView() {
        scnView = self.view as! SCNView
        scnView.showsStatistics = true
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.delegate = self
        scnView.playing = true
    }
    
    func setupScene() {
        scnScene = SCNScene()
        scnView.scene = scnScene
    }
    
    func setupCamera() {
        cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zFar = 1000
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 50)
        scnScene.rootNode.addChildNode(cameraNode)
    }
    
    func setupColorGrid() {
        for n in 0..<FREQ_BANDS {
            let color = colorForBand(n)
            colorByBand.append(color)
            colorByBandRed.append(color.components.red)
            colorByBandGreen.append(color.components.green)
            colorByBandBlue.append(color.components.blue)
        }
    }
    
    func setupGrid() {
        switch visualizationType {
        case .Rectangle:
            setupGridRectangle()
        case .Spiral:
            setupGridSpiral()
        }
    }
    
    func setupGridRectangle() {
        let gridWidth = 32
        for x in 0..<FREQ_BANDS {
            let ax = -gridWidth/2 + x % gridWidth
            let az = Int(x / gridWidth)
            let node = createCube(width: 1.0, length: 1.0, position: SCNVector3(ax,0,-az))
            grid.append(node)
            scnScene.rootNode.addChildNode(node)
        }
    }
    
    func setupGridSpiral() {
        for i in 0..<FREQ_BANDS {
            let r = Float(i) / 20.0
            let s = Float(i) / 100.0
            let x = s * cos(r)
            let z = s * sin(r)
            let node = createCube(width: 1.0, length: 1.0, position: SCNVector3(x,0,20+z))
            grid.append(node)
            scnScene.rootNode.addChildNode(node)
        }
    }
    
    func createCube(width width: CGFloat, length: CGFloat, position: SCNVector3) -> SCNNode {
        var geometry: SCNGeometry
        geometry = SCNBox(width: width, height: 1.0, length: length, chamferRadius: 0.3)
        let geometryNode = SCNNode(geometry: geometry)
        geometryNode.position = position
        return geometryNode
    }
}

extension GameViewController: SCNSceneRendererDelegate {
    func renderer(renderer: SCNSceneRenderer, updateAtTime time: NSTimeInterval) {
        getFrequencyOnRender()
    }
}

// MARK: - Audio
extension GameViewController {
    
    func colorForBand(n: Int) -> UIColor {
        return UIColor(hue: CGFloat(n) / CGFloat(FREQ_BANDS), saturation: 1.0, brightness: 1.0, alpha: 1.0)
    }
    
    func setupAudio() {
        
        for n in 0..<FREQ_BANDS {
            let color:CGColorRef = colorForBand(n).CGColor
            layers.append(CALayer())
            
            layers[n].backgroundColor = color
            layers[n].frame = CGRectZero
            self.view.layer.addSublayer(layers[n])
        }
        
        superpowered = Superpowered()
        
    }
    
    func getFrequencyOnRender() {
        // Get the frequency values.
        let frequencies = UnsafeMutablePointer<Float>.alloc(FREQ_BANDS)
        superpowered.getFrequencies(frequencies)
        
        // Wrapping the UI changes in a CATransaction block like this prevents animation/smoothing.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0)
        CATransaction.setDisableActions(true)
        
        // Set the dimension of every frequency bar.
        let originY:CGFloat = self.view.frame.size.height - 40
        let width:CGFloat = 320.0 / CGFloat(NUM_BANDS)
        var frame:CGRect = CGRectMake(20, 0, width, 0)
        for n in 0..<FREQ_BANDS {
            frame.size.height = 1+CGFloat(frequencies[n]) * 4000
            frame.origin.y = originY - frame.size.height
            layers[n].frame = frame
            frame.origin.x += width
            
            if n < grid.count {
                let amt = Float(frequencies[n] * 200)
                grid[n].scale = SCNVector3(1, amt*2.0, 1)
                grid[n].position.y = amt
                var opacity = CGFloat(amt) / 5.0
                if opacity > 1 {
                    opacity = 1.0
                }
                let newColor = UIColor(red: 0.3 + colorByBandRed[n] * opacity * 0.7,
                                        green: 0.3 + colorByBandGreen[n] * opacity * 0.7,
                                        blue: 0.3 + colorByBandBlue[n] * opacity * 0.7,
                                        alpha: 1.0)
                grid[n].geometry?.materials.first?.diffuse.contents = newColor
                grid[n].geometry?.materials.first?.emission.contents = newColor
//                grid[n].opacity = opacity//CGFloat(amt) / 400.0
            }
        }
        
        CATransaction.commit()
        frequencies.dealloc(FREQ_BANDS)
    }
}

