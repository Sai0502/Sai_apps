#!/usr/bin/env python3
# 给 Rigongyizu.xcodeproj 增量添加 Widget target + App Group（基于官方 objectVersion 77 格式）
import shutil, sys

PATH = '/Users/sai/Downloads/Sai_Apps/Rigongyizu/Rigongyizu.xcodeproj/project.pbxproj'
shutil.copy(PATH, PATH + '.prewidget')
s = open(PATH, encoding='utf-8').read()

W = '5000000000000000000000'  # id 前缀
IDs = {
    'appex_ref': W+'01',   # RigongyizuWidget.appex
    'sync_group': W+'02',  # RigongyizuWidget
    'embed_bf': W+'03',    # appex in Embed Foundation Extensions
    'wf_fw': W+'04',       # Frameworks
    'wf_res': W+'05',      # Resources
    'wf_src': W+'06',      # Sources
    'wt_target': W+'07',   # RigongyizuWidget native target
    'wt_cfglist': W+'08',
    'wt_dbg': W+'09',
    'wt_rel': W+'0A',
    'proxy': W+'0B',
    'dep': W+'0C',
    'embed_phase': W+'0D', # Embed Foundation Extensions (主 target)
    'ent_app': W+'0E',     # Rigongyizu.entitlements
    'ent_wid': W+'0F',     # RigongyizuWidget.entitlements
}

def insert_section(text, section_comment, new_block):
    """把 new_block 插到 '<section_comment> section */' 注释行之后（新行）。"""
    marker = '/* Begin %s section */' % section_comment
    idx = text.index(marker) + len(marker)
    # 插到该行末（保持原行尾换行符后面）
    nl = text.index('\n', idx)
    return text[:nl+1] + new_block + text[nl+1:]

# ---- 1. PBXFileReference：appex + 2 entitlements ----
blk1 = ('\t\t%s /* RigongyizuWidget.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = RigongyizuWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; };\n'
        '\t\t%s /* Rigongyizu.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Rigongyizu.entitlements; sourceTree = "<group>"; };\n'
        '\t\t%s /* RigongyizuWidget.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = RigongyizuWidget.entitlements; sourceTree = "<group>"; };\n') % (IDs['appex_ref'], IDs['ent_app'], IDs['ent_wid'])
s = insert_section(s, 'PBXFileReference', blk1)

# ---- 2. PBXFileSystemSynchronizedRootGroup ----
blk2 = ('\t\t%s /* RigongyizuWidget */ = {\n'
        '\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n'
        '\t\t\tpath = RigongyizuWidget;\n'
        '\t\t\tsourceTree = "<group>";\n'
        '\t\t};\n') % IDs['sync_group']
s = insert_section(s, 'PBXFileSystemSynchronizedRootGroup', blk2)

# ---- 3. PBXFrameworksBuildPhase ----
blk3 = ('\t\t%s /* Frameworks */ = {\n'
        '\t\t\tisa = PBXFrameworksBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tfiles = (\n'
        '\t\t\t);\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n') % IDs['wf_fw']
s = insert_section(s, 'PBXFrameworksBuildPhase', blk3)

# ---- 4. PBXGroup：main children + Products ----
s = s.replace(
    '\t\t\tchildren = (\n\t\t\t\t%s /* Rigongyizu */,\n\t\t\t\t%s /* Products */,\n\t\t\t);\n' % ('3272EA32309243920019A506', '3272EA31309243920019A506'),
    '\t\t\tchildren = (\n\t\t\t\t%s /* Rigongyizu */,\n\t\t\t\t%s /* RigongyizuWidget */,\n\t\t\t\t%s /* Rigongyizu.entitlements */,\n\t\t\t\t%s /* RigongyizuWidget.entitlements */,\n\t\t\t\t%s /* Products */,\n\t\t\t);\n' % ('3272EA32309243920019A506', IDs['sync_group'], IDs['ent_app'], IDs['ent_wid'], '3272EA31309243920019A506'))
s = s.replace(
    '\t\t\tchildren = (\n\t\t\t\t%s /* Rigongyizu.app */,\n\t\t\t);\n' % '3272EA30309243920019A506',
    '\t\t\tchildren = (\n\t\t\t\t%s /* Rigongyizu.app */,\n\t\t\t\t%s /* RigongyizuWidget.appex */,\n\t\t\t);\n' % ('3272EA30309243920019A506', IDs['appex_ref']))

# ---- 5. PBXNativeTarget：widget target + 主 target 增 embed/dependency ----
wt = ('\t\t%s /* RigongyizuWidget */ = {\n'
      '\t\t\tisa = PBXNativeTarget;\n'
      '\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "RigongyizuWidget" */;\n'
      '\t\t\tbuildPhases = (\n'
      '\t\t\t\t%s /* Sources */,\n'
      '\t\t\t\t%s /* Frameworks */,\n'
      '\t\t\t\t%s /* Resources */,\n'
      '\t\t\t);\n'
      '\t\t\tbuildRules = (\n'
      '\t\t\t);\n'
      '\t\t\tdependencies = (\n'
      '\t\t\t);\n'
      '\t\t\tfileSystemSynchronizedGroups = (\n'
      '\t\t\t\t%s /* RigongyizuWidget */,\n'
      '\t\t\t);\n'
      '\t\t\tname = RigongyizuWidget;\n'
      '\t\t\tpackageProductDependencies = (\n'
      '\t\t\t);\n'
      '\t\t\tproductName = RigongyizuWidget;\n'
      '\t\t\tproductReference = %s /* RigongyizuWidget.appex */;\n'
      '\t\t\tproductType = "com.apple.product-type.app-extension";\n'
      '\t\t};\n') % (IDs['wt_target'], IDs['wt_cfglist'], IDs['wf_src'], IDs['wf_fw'], IDs['wf_res'], IDs['sync_group'], IDs['appex_ref'])
s = insert_section(s, 'PBXNativeTarget', wt)

# 主 target buildPhases 追加 embed phase；dependencies 追加
s = s.replace(
    '\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n\t\t\t);\n' % ('3272EA2C309243920019A506', '3272EA2D309243920019A506', '3272EA2E309243920019A506'),
    '\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t\t%s /* Resources */,\n\t\t\t\t%s /* Embed Foundation Extensions */,\n\t\t\t);\n' % ('3272EA2C309243920019A506', '3272EA2D309243920019A506', '3272EA2E309243920019A506', IDs['embed_phase']))
s = s.replace(
    '\t\t\tdependencies = (\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t3272EA32309243920019A506 /* Rigongyizu */,\n\t\t\t);',
    '\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t3272EA32309243920019A506 /* Rigongyizu */,\n\t\t\t);' % IDs['dep'])

# ---- 6. PBXProject：targets + TargetAttributes ----
s = s.replace(
    '\t\t\tTargetAttributes = {\n\t\t\t\t%s = {\n\t\t\t\t\tCreatedOnToolsVersion = 26.3;\n\t\t\t\t};\n\t\t\t};\n' % '3272EA2F309243920019A506',
    '\t\t\tTargetAttributes = {\n\t\t\t\t%s = {\n\t\t\t\t\tCreatedOnToolsVersion = 26.3;\n\t\t\t\t};\n\t\t\t\t%s = {\n\t\t\t\t\tCreatedOnToolsVersion = 26.3;\n\t\t\t\t};\n\t\t\t};\n' % ('3272EA2F309243920019A506', IDs['wt_target']))
s = s.replace(
    '\t\t\ttargets = (\n\t\t\t\t%s /* Rigongyizu */,\n\t\t\t);\n' % '3272EA2F309243920019A506',
    '\t\t\ttargets = (\n\t\t\t\t%s /* Rigongyizu */,\n\t\t\t\t%s /* RigongyizuWidget */,\n\t\t\t);\n' % ('3272EA2F309243920019A506', IDs['wt_target']))

# ---- 7/8. Resources / Sources phases ----
blk7 = ('\t\t%s /* Resources */ = {\n'
        '\t\t\tisa = PBXResourcesBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tfiles = (\n'
        '\t\t\t);\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n') % IDs['wf_res']
s = insert_section(s, 'PBXResourcesBuildPhase', blk7)
blk8 = ('\t\t%s /* Sources */ = {\n'
        '\t\t\tisa = PBXSourcesBuildPhase;\n'
        '\t\t\tbuildActionMask = 2147483647;\n'
        '\t\t\tfiles = (\n'
        '\t\t\t);\n'
        '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        '\t\t};\n') % IDs['wf_src']
s = insert_section(s, 'PBXSourcesBuildPhase', blk8)

# ---- 9. PBXCopyFilesBuildPhase（新建 section）----
copy_phase = ('/* Begin PBXCopyFilesBuildPhase section */\n'
              '\t\t%s /* Embed Foundation Extensions */ = {\n'
              '\t\t\tisa = PBXCopyFilesBuildPhase;\n'
              '\t\t\tbuildActionMask = 2147483647;\n'
              '\t\t\tdstPath = "";\n'
              '\t\t\tdstSubfolderSpec = 13;\n'
              '\t\t\tfiles = (\n'
              '\t\t\t\t%s /* RigongyizuWidget.appex in Embed Foundation Extensions */,\n'
              '\t\t\t);\n'
              '\t\t\tname = "Embed Foundation Extensions";\n'
              '\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
              '\t\t};\n'
              '/* End PBXCopyFilesBuildPhase section */\n') % (IDs['embed_phase'], IDs['embed_bf'])
# 插到 PBXContainerItemProxy section 之前（若存在）否则放 PBXFileReference 前
if '/* Begin PBXContainerItemProxy section */' in s:
    idx = s.index('/* Begin PBXContainerItemProxy section */')
else:
    idx = s.index('/* Begin PBXFileReference section */')
s = s[:idx] + copy_phase + s[idx:]

# ---- 10/11. PBXContainerItemProxy + PBXTargetDependency ----
proxy = ('/* Begin PBXContainerItemProxy section */\n'
         '\t\t%s /* PBXContainerItemProxy */ = {\n'
         '\t\t\tisa = PBXContainerItemProxy;\n'
         '\t\t\tcontainerPortal = 3272EA28309243920019A506 /* Project object */;\n'
         '\t\t\tproxyType = 1;\n'
         '\t\t\tremoteGlobalIDString = %s;\n'
         '\t\t\tremoteInfo = RigongyizuWidget;\n'
         '\t\t};\n'
         '/* End PBXContainerItemProxy section */\n'
         '/* Begin PBXTargetDependency section */\n'
         '\t\t%s /* PBXTargetDependency */ = {\n'
         '\t\t\tisa = PBXTargetDependency;\n'
         '\t\t\ttarget = %s /* RigongyizuWidget */;\n'
         '\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n'
         '\t\t};\n'
         '/* End PBXTargetDependency section */\n') % (IDs['proxy'], IDs['wt_target'], IDs['dep'], IDs['wt_target'], IDs['proxy'])
idx = s.index('/* Begin PBXNativeTarget section */')
s = s[:idx] + proxy + s[idx:]

# ---- 12. XCBuildConfiguration：Widget Debug/Release ----
ws = ('\t\t%s /* Debug */ = {\n'
      '\t\t\tisa = XCBuildConfiguration;\n'
      '\t\t\tbuildSettings = {\n'
      '\t\t\t\tCODE_SIGN_ENTITLEMENTS = RigongyizuWidget.entitlements;\n'
      '\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
      '\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n'
      '\t\t\t\tDEVELOPMENT_TEAM = Q8N2JQA48S;\n'
      '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
      '\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "日拱一卒";\n'
      '\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";\n'
      '\t\t\t\tINFOPLIST_KEY_NSExtensionPointIdentifier = "com.apple.widgetkit-extension";\n'
      '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n'
      '\t\t\t\tMARKETING_VERSION = 1.0;\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jiangsai.rigongyizu.Widget;\n'
      '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
      '\t\t\t\tSDKROOT = iphoneos;\n'
      '\t\t\t\tSKIP_INSTALL = YES;\n'
      '\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n'
      '\t\t\t\tSWIFT_VERSION = 5.0;\n'
      '\t\t\t\tTARGETED_DEVICE_FAMILY = 1;\n'
      '\t\t\t};\n'
      '\t\t\tname = Debug;\n'
      '\t\t};\n'
      '\t\t%s /* Release */ = {\n'
      '\t\t\tisa = XCBuildConfiguration;\n'
      '\t\t\tbuildSettings = {\n'
      '\t\t\t\tCODE_SIGN_ENTITLEMENTS = RigongyizuWidget.entitlements;\n'
      '\t\t\t\tCODE_SIGN_STYLE = Automatic;\n'
      '\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n'
      '\t\t\t\tDEVELOPMENT_TEAM = Q8N2JQA48S;\n'
      '\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n'
      '\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "日拱一卒";\n'
      '\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";\n'
      '\t\t\t\tINFOPLIST_KEY_NSExtensionPointIdentifier = "com.apple.widgetkit-extension";\n'
      '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n'
      '\t\t\t\tMARKETING_VERSION = 1.0;\n'
      '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.jiangsai.rigongyizu.Widget;\n'
      '\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\n'
      '\t\t\t\tSDKROOT = iphoneos;\n'
      '\t\t\t\tSKIP_INSTALL = YES;\n'
      '\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n'
      '\t\t\t\tSWIFT_VERSION = 5.0;\n'
      '\t\t\t\tTARGETED_DEVICE_FAMILY = 1;\n'
      '\t\t\t};\n'
      '\t\t\tname = Release;\n'
      '\t\t};\n') % (IDs['wt_dbg'], IDs['wt_rel'])
s = insert_section(s, 'XCBuildConfiguration', ws)

# ---- 13. XCConfigurationList ----
cl = ('\t\t%s /* Build configuration list for PBXNativeTarget "RigongyizuWidget" */ = {\n'
      '\t\t\tisa = XCConfigurationList;\n'
      '\t\t\tbuildConfigurations = (\n'
      '\t\t\t\t%s /* Debug */,\n'
      '\t\t\t\t%s /* Release */,\n'
      '\t\t\t);\n'
      '\t\t\tdefaultConfigurationIsVisible = 0;\n'
      '\t\t\tdefaultConfigurationName = Release;\n'
      '\t\t};\n') % (IDs['wt_cfglist'], IDs['wt_dbg'], IDs['wt_rel'])
s = insert_section(s, 'XCConfigurationList', cl)

# ---- 14. 主 target 加 CODE_SIGN_ENTITLEMENTS ----
s = s.replace(
    '\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n\t\t\t\tDEVELOPMENT_TEAM = Q8N2JQA48S;\n\t\t\t\tENABLE_PREVIEWS = YES;',
    '\t\t\t\tCODE_SIGN_ENTITLEMENTS = Rigongyizu.entitlements;\n\t\t\t\tCODE_SIGN_STYLE = Automatic;\n\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n\t\t\t\tDEVELOPMENT_TEAM = Q8N2JQA48S;\n\t\t\t\tENABLE_PREVIEWS = YES;')

open(PATH, 'w', encoding='utf-8').write(s)
print('PATCHED OK; braces', s.count('{'), s.count('}'))
