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
    var gridNode: SCNNode!
    var frameCount = 0
    
    var volumeInBand: [CGFloat] = [] // 0 to 1.0
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
        addGestureRecognizer()
    }
    
    func addGestureRecognizer() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scnView.addGestureRecognizer(tapGesture)
    }
    
    func handleTap(gestureRecognize: UIGestureRecognizer) {
        print("handleTap")
        if visualizationType == .Spiral {
            visualizationType = .Rectangle
            configGridRectangle()
        } else {
            visualizationType = .Spiral
            configGridSpiral()
        }
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
        gridNode = SCNNode()
        scnScene.rootNode.addChildNode(gridNode)
    }
    
    func setupColorGrid() {
        for n in 0..<FREQ_BANDS {
            let color = colorForBand(n)
            volumeInBand.append(0)
            colorByBand.append(color)
            colorByBandRed.append(color.components.red)
            colorByBandGreen.append(color.components.green)
            colorByBandBlue.append(color.components.blue)
        }
    }
    
    func setupGrid() {
        for _ in 0..<FREQ_BANDS {
            let node = createCube(width: 1.0, length: 1.0, position: SCNVector3(0,0,0))
            grid.append(node)
            gridNode.addChildNode(node)
        }
        switch visualizationType {
        case .Rectangle:
            configGridRectangle()
        case .Spiral:
            configGridSpiral()
        }
        setupGridAutoRotation()
    }
    
    func setupGridAutoRotation() {
        self.gridNode.runAction(SCNAction.repeatActionForever(SCNAction.rotateByX(0, y: 2*CGFloat(M_PI), z: 0, duration: 30)))
    }
    
    func configGridRectangle() {
        let gridWidth = 32
        let gridDepth = FREQ_BANDS / gridWidth
        for i in 0..<FREQ_BANDS {
            let ax = -gridWidth/2 + i % gridWidth
            let az = Int(i / gridWidth) - gridDepth / 2
            grid[i].position.x = Float(ax)
            grid[i].position.y = 0
            grid[i].position.z = Float(-az)
        }
    }
    
    func configGridSpiral() {
        for i in 0..<FREQ_BANDS {
            let r = Float(i) / 20.0
            let s = Float(i) / 100.0
            let x = s * cos(r)
            let z = s * sin(r)
            grid[i].position.x = Float(x)
            grid[i].position.y = 0
            grid[i].position.z = Float(z)
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
        frameCount += 1
    }
}

// MARK: - Audio
extension GameViewController {
    
    func colorForBand(n: Int) -> UIColor {
        let range = CGFloat(0.8)
        let t = CGFloat(n) / CGFloat(FREQ_BANDS)
        
        return UIColor(hue: t * range, saturation: 1.0, brightness: 1.0, alpha: 1.0)
    }
    
    func setupAudio() {
        
        for n in 0..<FREQ_BANDS {
            let color = colorForBand(n)
            let newColor = UIColor(red: 0.5 + color.components.red * 0.5,
                                   green: 0.5 + color.components.green * 0.5,
                                   blue: 0.5 + color.components.blue * 0.5, alpha: 1.0)
            let newCGColor = newColor.CGColor
            layers.append(CALayer())
            
            layers[n].backgroundColor = newCGColor
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
            frame.size.height = 4 + CGFloat(frequencies[n]) * 4000
            frame.origin.y = originY - frame.size.height
            layers[n].frame = frame
            frame.origin.x += width
            
            if n < grid.count {
                let amt = Float(frequencies[n] * 200)
                grid[n].scale = SCNVector3(1, amt*2.0, 1)
                grid[n].position.y = amt
                
                var volume = CGFloat(amt) / 5.0
                if volume > 1 {
                    volume = 1.0
                }
                volumeInBand[n] = volume
            }
        }
        
        CATransaction.commit()
        frequencies.dealloc(FREQ_BANDS)
        
//        if (frameCount % 20 == 0) {
            for n in 0..<FREQ_BANDS {
                let volume = volumeInBand[n]
                let scaledVolume = volume * 0.8
                let newColor = UIColor(red: 0.2 + colorByBandRed[n] * scaledVolume,
                                       green: 0.2 + colorByBandGreen[n] * scaledVolume,
                                       blue: 0.2 + colorByBandBlue[n] * scaledVolume,
                                       alpha: 1.0)

                grid[n].geometry?.materials.first?.diffuse.contents = newColor
                grid[n].geometry?.materials.first?.emission.contents = newColor
            }
        }
//    }
}

