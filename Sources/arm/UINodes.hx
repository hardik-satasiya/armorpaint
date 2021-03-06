package arm;

import armory.system.Cycles;
import zui.*;
import zui.Nodes;
import iron.data.SceneFormat;
import iron.data.MaterialData;

@:access(zui.Zui)
class UINodes extends iron.Trait {

	public static var inst:UINodes;

	public var show = false;
	public var wx:Int;
	public var wy:Int;
	public var ww:Int;

	public var ui:Zui;
	var drawMenu = false;
	var showMenu = false;
	var hideMenu = false;
	var menuCategory = 0;
	var addNodeButton = false;
	var popupX = 0.0;
	var popupY = 0.0;

	var sc:iron.data.ShaderData.ShaderContext = null;
	public var _matcon:TMaterialContext = null;
	var _materialcontext:MaterialContext = null;

	public var nodes = new Nodes();
	public var canvas:TNodeCanvas = null;
	var canvasMap:Map<UITrait.MaterialSlot, TNodeCanvas> = null;
	var canvasBlob:String;

	public var canvasBrush:TNodeCanvas = null;
	var canvasBrushMap:Map<UITrait.BrushSlot, TNodeCanvas> = null;
	var canvasBrushBlob:String;
	public var isBrush = false;

	public function new() {
		super();
		inst = this;

		iron.data.Data.getBlob('default_material.json', function(b1:kha.Blob) {
			iron.data.Data.getBlob('default_brush.json', function(b2:kha.Blob) {

				canvasBlob = b1.toString();
				canvasBrushBlob = b2.toString();

				kha.Assets.loadImageFromPath('color_wheel.png', false, function(image:kha.Image) {

					canvas = haxe.Json.parse(canvasBlob);
					canvasBrush = haxe.Json.parse(canvasBrushBlob);
					parseBrush();

					var t = Reflect.copy(zui.Themes.dark);
					t.FILL_WINDOW_BG = true;
					t.ELEMENT_H = 18;
					t.BUTTON_H = 16;
					var scale = armory.data.Config.raw.window_scale;
					ui = new Zui({font: arm.App.font, theme: t, color_wheel: image, scaleFactor: scale});
					ui.scrollEnabled = false;
					
					notifyOnRender2D(render2D);
					notifyOnUpdate(update);
				});
			});
		});
	}

	public function updateCanvasMap() {
		if (UITrait.inst.selected != null) {
			if (canvasMap == null) canvasMap = new Map();
			var c = canvasMap.get(UITrait.inst.selected);
			if (c == null) {
				c = haxe.Json.parse(canvasBlob);
				canvasMap.set(UITrait.inst.selected, c);
				canvas = c;
			}
			else canvas = c;

			if (!isBrush) nodes = UITrait.inst.selected.nodes;
		}
	}

	public function updateCanvasBrushMap() {
		if (UITrait.inst.selectedBrush != null) {
			if (canvasBrushMap == null) canvasBrushMap = new Map();
			var c = canvasBrushMap.get(UITrait.inst.selectedBrush);
			if (c == null) {
				c = haxe.Json.parse(canvasBrushBlob);
				canvasBrushMap.set(UITrait.inst.selectedBrush, c);
				canvasBrush = c;
			}
			else canvasBrush = c;

			if (isBrush) nodes = UITrait.inst.selectedBrush.nodes;
		}
	}

	var mx = 0.0;
	var my = 0.0;
	var frame = 0;
	var mdown = false;
	var mreleased = false;
	var mchanged = false;
	public var changed = false;
	function update() {
		if (frame == 8) {
			parseMeshMaterial();
			parsePaintMaterial(); // Temp cpp fix
		}
		frame++;

		updateCanvasMap();
		updateCanvasBrushMap();

		var mouse = iron.system.Input.getMouse();
		mreleased = mouse.released();
		mdown = mouse.down();

		if (ui.changed) {
			mchanged = true;
			if (!mdown) changed = true;
			if (isBrush) parseBrush();
		}
		if ((mreleased && mchanged) || changed) {
			mchanged = changed = false;
			if (!isBrush) parsePaintMaterial();
		}

		if (!show) return;
		if (!arm.App.uienabled) return;
		var keyboard = iron.system.Input.getKeyboard();

		wx = Std.int(iron.App.w());
		wy = 0;
		if (mouse.x < wx || mouse.y < wy) return;
		if (ui.isTyping) return;

		if (mouse.started("right")) {
			mx = mouse.x;
			my = mouse.y;
		}
		else if (addNodeButton) {
			showMenu = true;
			addNodeButton = false;
		}
		else if (mouse.released()) {
			hideMenu = true;
		}

		if (keyboard.started("x") || keyboard.started("backspace")) {
			var c = isBrush ? canvasBrush : canvas;
			nodes.removeNode(nodes.nodeSelected, c);
			changed = true;
		}

		if (keyboard.started("p")) {
			var c = isBrush ? canvasBrush : canvas;
			trace(haxe.Json.stringify(c));
		}
	}

	public function getNodeX():Int {
		var mouse = iron.system.Input.getMouse();
		return Std.int((mouse.x - wx - nodes.PAN_X()) / nodes.SCALE);
	}

	public function getNodeY():Int {
		var mouse = iron.system.Input.getMouse();
		return Std.int((mouse.y - wy - nodes.PAN_Y()) / nodes.SCALE);
	}

	public var grid:kha.Image = null;
	public function drawGrid() {
		var ww = iron.App.w();
		var wh = iron.App.h();
		var w = ww + 40 * 2;
		var h = wh + 40 * 2;
		grid = kha.Image.createRenderTarget(w, h);
		grid.g2.begin(true, 0xff242424);
		for (i in 0...Std.int(h / 40) + 1) {
			grid.g2.color = 0xff282828;
			grid.g2.drawLine(0, i * 40, w, i * 40);
			grid.g2.color = 0xff323232;
			grid.g2.drawLine(0, i * 40 + 20, w, i * 40 + 20);
		}
		for (i in 0...Std.int(w / 40) + 1) {
			grid.g2.color = 0xff282828;
			grid.g2.drawLine(i * 40, 0, i * 40, h);
			grid.g2.color = 0xff323232;
			grid.g2.drawLine(i * 40 + 20, 0, i * 40 + 20, h);
		}
		grid.g2.end();
	}

	public var hwnd = Id.handle();

	function render2D(g:kha.graphics2.Graphics) {
		if (!show) return;
		
		if (!arm.App.uienabled && ui.inputRegistered) ui.unregisterInput();
		if (arm.App.uienabled && !ui.inputRegistered) ui.registerInput();
		
		g.end();

		if (grid == null) drawGrid();

		// Start with UI
		ui.begin(g);
		// ui.begin(rt.g2); ////
		
		// Make window
		ww = Std.int(iron.App.w());
		wx = Std.int(iron.App.w());
		wy = 0;
		if (ui.window(hwnd, wx, wy, ww, iron.App.h())) {
			
			ui.g.color = 0xffffffff;
			ui.g.drawImage(grid, (nodes.panX * nodes.SCALE) % 40 - 40, (nodes.panY * nodes.SCALE) % 40 - 40);

			ui.g.font = arm.App.font;
			ui.g.fontSize = 22;
			var title = isBrush ? "Brush" : "Material";
			var titlew = ui.g.font.width(22, title);
			var titleh = ui.g.font.height(22);
			ui.g.drawString(title, ww - titlew - 20, iron.App.h() - titleh - 10);
			
			// Recompile material on change
			ui.changed = false;
			var c = isBrush ? canvasBrush : canvas;
			nodes.nodeCanvas(ui, c);

			ui.g.color = ui.t.WINDOW_BG_COL;
			ui.g.fillRect(0, 0, ww, 24);
			ui.g.color = 0xffffffff;

			ui._x = 3;
			ui._y = 3;
			ui._w = 105;

			if (isBrush) {
				if (ui.button("Nodes")) { addNodeButton = true; menuCategory = 0; popupX = wx + ui._x; popupY = wy + ui._y; }
			}
			else {
				if (ui.button("Input")) { addNodeButton = true; menuCategory = 0; popupX = wx + ui._x; popupY = wy + ui._y; }
				ui._x += 105 + 3;
				ui._y = 3;
				if (ui.button("Output")) { addNodeButton = true; menuCategory = 1; popupX = wx + ui._x; popupY = wy + ui._y; }
				ui._x += 105 + 3;
				ui._y = 3;
				if (ui.button("Texture")) { addNodeButton = true; menuCategory = 2; popupX = wx + ui._x; popupY = wy + ui._y; }
				ui._x += 105 + 3;
				ui._y = 3;
				if (ui.button("Color")) { addNodeButton = true; menuCategory = 3; popupX = wx + ui._x; popupY = wy + ui._y; }
				ui._x += 105 + 3;
				ui._y = 3;
				if (ui.button("Converter")) { addNodeButton = true; menuCategory = 4; popupX = wx + ui._x; popupY = wy + ui._y; }
			}
		}

		ui.endWindow();

		if (drawMenu) {
			
			var numNodes = isBrush ? NodeCreatorBrush.numNodes[menuCategory] : NodeCreator.numNodes[menuCategory];
			var ph = numNodes * 20;
			var py = popupY;
			g.color = 0xff222222;
			g.fillRect(popupX, py, 105, ph);

			ui.beginLayout(g, Std.int(popupX), Std.int(py), 105);
			
			isBrush ? NodeCreatorBrush.draw(menuCategory) : NodeCreator.draw(menuCategory);

			ui.endLayout();
		}

		ui.end();

		g.begin(false);

		if (showMenu) {
			showMenu = false;
			drawMenu = true;
			
		}
		if (hideMenu) {
			hideMenu = false;
			drawMenu = false;
		}
	}

	function make_paint(data:ShaderData, matcon:TMaterialContext):armory.system.ShaderContext {
		var context_id = 'paint';
		var con_paint:armory.system.ShaderContext = data.add_context({
			name: context_id,
			depth_write: false,
			compare_mode: 'always',
			cull_mode: 'counter_clockwise',
			blend_source: 'source_alpha', //blend_one
			blend_destination: 'inverse_source_alpha', //blend_zero
			blend_operation: 'add',
			alpha_blend_source: 'blend_one',
			alpha_blend_destination: 'blend_zero',
			alpha_blend_operation: 'add',
			vertex_structure: [{"name": "pos", "size": 3},{"name": "nor", "size": 3},{"name": "tex", "size": 2}] });

		if (UITrait.inst.brushType == 2) {
			con_paint.data.color_write_green = false; // R
			con_paint.data.color_write_blue = false; // M
		}

		var vert = con_paint.make_vert();
		var frag = con_paint.make_frag();

		vert.add_out('vec3 sp');
		frag.ins = vert.outs;
		vert.add_uniform('mat4 WVP', '_worldViewProjectionMatrix');
		vert.write('vec2 tpos = vec2(tex.x * 2.0 - 1.0, tex.y * 2.0 - 1.0);');

		// TODO: Fix seams at uv borders
		vert.add_uniform('vec2 sub', '_sub');
		vert.add_uniform('float paintDepthBias', '_paintDepthBias');
		vert.write('tpos += sub;');
		
		vert.write('gl_Position = vec4(tpos, 0.0, 1.0);');
		
		vert.write('vec4 ndc = WVP * vec4(pos, 1.0);');
		vert.write('ndc.xyz = ndc.xyz / ndc.w;');
		vert.write('sp.xyz = ndc.xyz * 0.5 + 0.5;');
		vert.write('sp.y = 1.0 - sp.y;');
		vert.write('sp.z -= 0.0001;'); // Bias
		vert.write('sp.z -= paintDepthBias;'); // paintVisible

		vert.add_out('vec3 mposition');
		if (UITrait.inst.brushPaint == 0 && con_paint.is_elem('tex')) {
        	vert.write('mposition = pos.xyz;');
        }
        else {
        	vert.write('mposition = ndc.xyz;');
        }

        if (UITrait.inst.brushType == 2) { // Bake ao
        	vert.add_out('vec3 wposition');
        	vert.add_uniform('mat4 W', '_worldMatrix');
        	vert.write('wposition = vec4(W * vec4(pos.xyz, 1.0)).xyz;');

        	vert.add_out('vec3 wnormal');
			vert.add_uniform('mat3 N', '_normalMatrix');
			vert.write('wnormal = N * nor;');
			frag.write('vec3 n = normalize(wnormal);');
    	}

		frag.add_uniform('vec4 inp', '_inputBrush');
		frag.add_uniform('vec4 inplast', '_inputBrushLast');
		frag.add_uniform('float aspectRatio', '_aspectRatioWindowF');
		frag.write('vec2 bsp = sp.xy * 2.0 - 1.0;');
		frag.write('bsp.x *= aspectRatio;');
		frag.write('bsp = bsp * 0.5 + 0.5;');

		frag.add_uniform('sampler2D paintdb');

		if (UITrait.inst.brushType == 3) { // Pick color id
			frag.add_out('vec4 fragColor');

			frag.write('if (sp.z > texture(paintdb, vec2(sp.x, 1.0 - bsp.y)).r) discard;');
			frag.write('vec2 binp = inp.xy * 2.0 - 1.0;');
			frag.write('binp.x *= aspectRatio;');
			frag.write('binp = binp * 0.5 + 0.5;');
			
			frag.write('float dist = distance(bsp.xy, binp.xy);');
			frag.write('if (dist > 0.025) discard;'); // Base this on camera zoom - more for zommed in camera, less for zoomed out

			frag.add_uniform('sampler2D texcolorid', '_texcolorid');
			vert.add_out('vec2 texCoord');
			vert.write('texCoord = fract(tex);'); // TODO: fract(tex) - somehow clamp is set after first paint
			frag.write('vec3 idcol = texture(texcolorid, texCoord).rgb;');
			frag.write('fragColor = vec4(idcol, 1.0);');

			con_paint.data.shader_from_source = true;
			con_paint.data.vertex_shader = vert.get();
			con_paint.data.fragment_shader = frag.get();
			return con_paint;
		}

		frag.add_out('vec4 fragColor[3]');

		frag.add_uniform('float brushRadius', '_brushRadius');
		frag.add_uniform('float brushOpacity', '_brushOpacity');
		frag.add_uniform('float brushStrength', '_brushStrength');

		if (UITrait.inst.brushType == 0) { // Draw
			frag.write('if (sp.z > texture(paintdb, vec2(sp.x, 1.0 - bsp.y)).r) { discard; return; }');
			
			frag.write('vec2 binp = inp.xy * 2.0 - 1.0;');
			frag.write('binp.x *= aspectRatio;');
			frag.write('binp = binp * 0.5 + 0.5;');

			// Continuos paint
			frag.write('vec2 binplast = inplast.xy * 2.0 - 1.0;');
			frag.write('binplast.x *= aspectRatio;');
			frag.write('binplast = binplast * 0.5 + 0.5;');
			
			frag.write('vec2 pa = bsp.xy - binp.xy, ba = binplast.xy - binp.xy;');
		    frag.write('float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);');
		    frag.write('float dist = length(pa - ba * h);');
		    frag.write('if (dist > brushRadius) { discard; return; }');
		    //

			
			// frag.write('float dist = distance(bsp.xy, binp.xy);');
			// frag.write('if (dist > brushRadius) { discard; return; }');

			
		}
		else {
			frag.write('float dist = 0.0;');
		}

		if (UITrait.inst.colorIdPicked) {
			frag.add_uniform('sampler2D texpaint_colorid0'); // 1x1 picker
			frag.add_uniform('sampler2D texcolorid', '_texcolorid'); // color map
			frag.add_uniform('vec2 texcoloridSize', '_texcoloridSize'); // color map
			frag.write('vec3 c1 = texelFetch(texpaint_colorid0, ivec2(0, 0), 0).rgb;');
			frag.write('vec3 c2 = texelFetch(texcolorid, ivec2(texCoord * texcoloridSize), 0).rgb;');
			frag.write('if (c1 != c2) { discard; return; }');
		}

		// Texture projection - texcoords
		if (UITrait.inst.brushPaint == 0 && con_paint.is_elem('tex')) {
			vert.add_uniform('float brushScale', '_brushScale');
			vert.add_out('vec2 texCoord');
			vert.write('texCoord = fract(tex * brushScale);'); // TODO: fract(tex) - somehow clamp is set after first paint
		}
		else {
			frag.add_uniform('float brushScale', '_brushScale');
			// TODO: use prescaled value from VS
			Cycles.texCoordName = 'fract(sp * brushScale)'; // Texture projection - project
		}
		var sout = Cycles.parse(canvas, con_paint, vert, frag, null, null, null, matcon);
		Cycles.texCoordName = 'texCoord';
		var base = sout.out_basecol;
		var rough = sout.out_roughness;
		var met = sout.out_metallic;
		var occ = sout.out_occlusion;
		var nortan = Cycles.out_normaltan;
		frag.write('vec3 basecol = $base;');
		frag.write('float roughness = $rough;');
		frag.write('float metallic = $met;');
		frag.write('float occlusion = $occ;');
		frag.write('vec3 nortan = $nortan;');

		frag.write('    float str = brushOpacity * clamp((brushRadius - dist) * brushStrength, 0.0, 1.0);');
		frag.write('    str = clamp(str, 0.0, 1.0);');

		frag.write('    fragColor[0] = vec4(basecol, str);');
		frag.write('    fragColor[1] = vec4(nortan, 1.0);');
		frag.write('    fragColor[2] = vec4(occlusion, roughness, metallic, str);');

		if (!UITrait.inst.paintBase) frag.write('fragColor[0].a = 0.0;');
		if (!UITrait.inst.paintNor) frag.write('fragColor[1].a = 0.0;');
		if (!UITrait.inst.paintRough) frag.write('fragColor[2].a = 0.0;');

		if (UITrait.inst.brushType == 2) { // Bake AO
			frag.write('fragColor[0].a = 0.0;');
			frag.write('fragColor[1].a = 0.0;');

			// frag.write('mat3 TBN = cotangentFrame(n, -vVec, texCoord);')
			// frag.write('n = nortan * 2.0 - 1.0;')
			// frag.write('n = normalize(TBN * normalize(n));')

			frag.write('const vec3 voxelgiHalfExtents = vec3(2.0);');
			frag.write('vec3 voxpos = wposition / voxelgiHalfExtents;');
       		frag.add_uniform('sampler3D voxels');
       		frag.add_function(armory.system.CyclesFunctions.str_traceAO);
			frag.write('fragColor[2].r = 1.0 - traceAO(voxpos, wnormal, voxels);');
		}

		con_paint.data.shader_from_source = true;
		con_paint.data.vertex_shader = vert.get();
		con_paint.data.fragment_shader = frag.get();

		return con_paint;
	}

	function make_mesh_preview(data:ShaderData, matcon:TMaterialContext):armory.system.ShaderContext {
		var context_id = 'mesh';
		var con_mesh:armory.system.ShaderContext = data.add_context({
			name: context_id,
			depth_write: true,
			compare_mode: 'less',
			cull_mode: 'clockwise' });

		var vert = con_mesh.make_vert();
		var frag = con_mesh.make_frag();

		
		frag.ins = vert.outs;
		vert.add_uniform('mat4 WVP', '_worldViewProjectionMatrix');
		vert.write('gl_Position = WVP * vec4(pos, 1.0);');


		var sout = Cycles.parse(canvas, con_mesh, vert, frag, null, null, null, matcon);
		var base = sout.out_basecol;
		var rough = sout.out_roughness;
		var met = sout.out_metallic;
		var occ = sout.out_occlusion;
		frag.write('vec3 basecol = $base;');
		frag.write('float roughness = $rough;');
		frag.write('float metallic = $met;');
		frag.write('float occlusion = $occ;');

		frag.add_out('vec4[2] fragColor');
		frag.write('fragColor[0] = vec4(0.0, 0.0, 0.0, 1.0 - gl_FragCoord.z);');
		frag.write('fragColor[1] = vec4(basecol.rgb, 0.0);');

		con_mesh.data.shader_from_source = true;
		con_mesh.data.vertex_shader = vert.get();
		con_mesh.data.fragment_shader = frag.get();

		return con_mesh;
	}

	function make_depth(data:ShaderData):armory.system.ShaderContext {
		var context_id = 'depth';
		var con_depth:armory.system.ShaderContext = data.add_context({
			name: context_id,
			depth_write: true,
			compare_mode: 'less',
			cull_mode: 'clockwise',
			color_write_red: false,
			color_write_green: false,
			color_write_blue: false,
			color_write_alpha: false });

		var vert = con_depth.make_vert();
		var frag = con_depth.make_frag();

		
		frag.ins = vert.outs;
		vert.add_uniform('mat4 WVP', '_worldViewProjectionMatrix');
		vert.write('gl_Position = WVP * vec4(pos, 1.0);');

		con_depth.data.shader_from_source = true;
		con_depth.data.vertex_shader = vert.get();
		con_depth.data.fragment_shader = frag.get();

		return con_depth;
	}

	function make_mesh_paint(data:ShaderData):armory.system.ShaderContext {
		var context_id = 'mesh';
		var con_mesh:armory.system.ShaderContext = data.add_context({
			name: context_id,
			depth_write: true,
			compare_mode: 'less',
			cull_mode: 'clockwise',
			vertex_structure: [{"name": "pos", "size": 3},{"name": "nor", "size": 3},{"name": "tex", "size": 2}] });

		var vert = con_mesh.make_vert();
		var frag = con_mesh.make_frag();

		vert.add_out('vec2 texCoord');
		vert.add_out('vec3 wnormal');
		vert.add_out('vec4 wvpposition');
		vert.add_out('vec4 prevwvpposition');
		vert.add_out('vec3 eyeDir');
		vert.add_uniform('mat3 N', '_normalMatrix');
		vert.add_uniform('mat4 WVP', '_worldViewProjectionMatrix');
		vert.add_uniform('mat4 prevWVP', '_prevWorldViewProjectionMatrix');
		vert.add_uniform('vec3 eye', '_cameraPosition');
		vert.add_uniform('mat4 W', '_worldMatrix');
		vert.write('vec4 spos = vec4(pos, 1.0);');
		vert.write('wnormal = normalize(N * nor);');
		vert.write('vec3 wposition = vec4(W * spos).xyz;');
		vert.write('gl_Position = WVP * spos;');
		vert.write('texCoord = tex;');
		vert.write('wvpposition = gl_Position;');
		vert.write('prevwvpposition = prevWVP * spos;');
		vert.write('eyeDir = eye - wposition;');

		frag.ins = vert.outs;

		frag.add_out('vec4[3] fragColor');
		frag.write('vec3 n = normalize(wnormal);');
		frag.add_function(armory.system.CyclesFunctions.str_packFloat);

		if (arm.UITrait.inst.brushType == 3) { // Show color map
			frag.add_uniform('sampler2D texcolorid', '_texcolorid');
			frag.write('fragColor[0] = vec4(n.xy, packFloat(1.0, 1.0), 1.0 - gl_FragCoord.z);');
			frag.write('vec3 idcol = pow(texture(texcolorid, texCoord).rgb, vec3(2.2));');
			frag.write('fragColor[1] = vec4(idcol.rgb, 1.0);');
		}
		else {
			frag.add_function(armory.system.CyclesFunctions.str_cotangentFrame);
			frag.add_function(armory.system.CyclesFunctions.str_octahedronWrap);

			frag.add_uniform('sampler2D texpaint');
			frag.add_uniform('sampler2D texpaint_nor');
			frag.add_uniform('sampler2D texpaint_pack');

			frag.write('vec3 vVec = normalize(eyeDir);');

			frag.write('vec3 basecol;');
			frag.write('float roughness;');
			frag.write('float metallic;');
			frag.write('float occlusion;');
			frag.write('float opacity;');

			frag.write('basecol = pow(texture(texpaint, texCoord).rgb, vec3(2.2));');

			frag.write('mat3 TBN = cotangentFrame(n, -vVec, texCoord);');
			frag.write('n = texture(texpaint_nor, texCoord).rgb * 2.0 - 1.0;');
			frag.write('n = normalize(TBN * normalize(n));');

			frag.write('vec4 pack = texture(texpaint_pack, texCoord);');
			frag.write('occlusion = pack.r;');
			frag.write('roughness = pack.g;');
			frag.write('metallic = pack.b;');

			frag.write('n /= (abs(n.x) + abs(n.y) + abs(n.z));');
			frag.write('n.xy = n.z >= 0.0 ? n.xy : octahedronWrap(n.xy);');
			frag.write('fragColor[0] = vec4(n.xy, packFloat(metallic, roughness), 1.0 - gl_FragCoord.z);');
			frag.write('fragColor[1] = vec4(basecol.rgb, occlusion);');
		}

		frag.write('vec2 posa = (wvpposition.xy / wvpposition.w) * 0.5 + 0.5;');
		frag.write('vec2 posb = (prevwvpposition.xy / prevwvpposition.w) * 0.5 + 0.5;');
		frag.write('fragColor[2].rg = vec2(posa - posb);');

		con_mesh.data.shader_from_source = true;
		con_mesh.data.vertex_shader = vert.get();
		con_mesh.data.fragment_shader = frag.get();

		return con_mesh;
	}

	function getMOut():Bool {
		for (n in canvas.nodes) if (n.type == "OUTPUT_MATERIAL_PBR") return true;
		return false;
	}

	public function parseMeshMaterial() {
		iron.data.Data.getMaterial("Scene", "Material", function(m:iron.data.MaterialData) {
			var sc:iron.data.ShaderData.ShaderContext = null;
			for (c in m.shader.contexts) if (c.raw.name == "mesh") { sc = c; break; }
			m.shader.raw.contexts.remove(sc.raw);
			m.shader.contexts.remove(sc);
			var con = make_mesh_paint(new ShaderData({name: "Material", canvas: null}));
			sc = new iron.data.ShaderData.ShaderContext(con.data, null, function(sc:iron.data.ShaderData.ShaderContext){});
			m.shader.raw.contexts.push(sc.raw);
			m.shader.contexts.push(sc);
		});
	}

	public function parsePaintMaterial() {
		UITrait.inst.dirty = true;

		if (getMOut()) {

			iron.data.Data.getMaterial("Scene", "Material", function(m:iron.data.MaterialData) {
			
				var mat:TMaterial = {
					name: "Material",
					canvas: canvas
				};
				var _sd = new ShaderData(mat);
				
				if (sc == null) {
					for (c in m.shader.contexts) {
						if (c.raw.name == "paint") {
							sc = c;
							break;
						}
					}
				}
				if (_materialcontext == null) {
					for (c in m.contexts) {
						if (c.raw.name == "paint") {
							_materialcontext = c;
							_matcon = c.raw;
							break;
						}
					}
				}

				if (sc != null) {
					m.shader.raw.contexts.remove(sc.raw);
					m.shader.contexts.remove(sc);
					m.raw.contexts.remove(_matcon);
					m.contexts.remove(_materialcontext);
				}

				_matcon = {
					name: "paint",
					bind_textures: []
				}

				var con = make_paint(_sd, _matcon);
				var cdata = con.data;

				// if (sc == null) {
					// from_source is synchronous..
					sc = new iron.data.ShaderData.ShaderContext(cdata, null, function(sc:iron.data.ShaderData.ShaderContext){});
					m.shader.raw.contexts.push(sc.raw);
					m.shader.contexts.push(sc);
					m.raw.contexts.push(_matcon);

					new MaterialContext(_matcon, function(self:MaterialContext) {
						_materialcontext = self;
						m.contexts.push(self);
					});



					var dcon = make_depth(_sd);
					var dcdata = dcon.data;
					// from_source is synchronous..
					var dsc = new iron.data.ShaderData.ShaderContext(dcdata, null, function(sc:iron.data.ShaderData.ShaderContext){});
					m.shader.contexts.push(dsc);
					var dmatcon:TMaterialContext = {
						name: "depth"
					}
					m.raw.contexts.push(dmatcon);
					new MaterialContext(dmatcon, function(self:MaterialContext) {
						m.contexts.push(self);
					});
				// }
				// else {
				// 	sc.raw.vertex_shader = cdata.vertex_shader;
				// 	sc.raw.fragment_shader = cdata.fragment_shader;
				// 	sc.compile();
				// }
			});
		}
	}

	public function acceptDrag(assetIndex:Int) {
		NodeCreator.createImageTexture();
		nodes.nodeSelected.buttons[0].default_value = assetIndex;
	}

	public function parseBrush() {
		armory.system.Logic.packageName = "arm.logicnode";
		var tree = armory.system.Logic.parse(canvasBrush, false);
	}
}
