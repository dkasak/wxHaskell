{--------------------------------------------------------------------------------
   List control demo.
--------------------------------------------------------------------------------}
module Main where

import Directory
import List( zip3 )
import Graphics.UI.WX
import Graphics.UI.WXCore 

main :: IO ()
main 
  = start gui

{--------------------------------------------------------------------------------
   Images
--------------------------------------------------------------------------------}
imgComputer   = "computer"
imgDisk       = "disk"
imgFile       = "file"
imgHFile      = "hsicon"
imgFolder     = "f_closed"
imgFolderOpen = "f_open"

imageNames    
  = [imgComputer,imgDisk,imgFile,imgHFile,imgFolder,imgFolderOpen]

imageFiles
  = map (\name -> "../bitmaps/" ++ name ++ ".ico") imageNames

imageIndex :: String -> Int
imageIndex name 
  = case lookup name (zip imageNames [0..]) of
      Just idx  -> idx
      Nothing   -> imageNone

imageNone :: Int
imageNone     = (-1)

{--------------------------------------------------------------------------------
   wrap the "unsafe" calls in to safe wrappers.
--------------------------------------------------------------------------------}
treeCtrlSetItemPath :: TreeCtrl a -> TreeItem -> FilePath -> IO ()
treeCtrlSetItemPath t item path
  = treeCtrlSetItemClientData t item (return ()) path

treeCtrlGetItemPath :: TreeCtrl a -> TreeItem -> IO FilePath 
treeCtrlGetItemPath t item
  = do mbpath <- unsafeTreeCtrlGetItemClientData t item
       case mbpath of
         Just path -> return path
         Nothing   -> return ""


{--------------------------------------------------------------------------------
   GUI
--------------------------------------------------------------------------------}
gui :: IO ()
gui
  = do -- main gui elements: frame, panel
       f       <- frame [text := "File browser"]
       -- panel: just for the nice grey color
       p       <- panel f []
      
       -- image list
       images  <- imageListCreate (sz 16 16) True 2
       imageListAddIconsFromFiles images imageFiles

       s <- splitterWindowCreate p idAny rectNull wxSP_LIVE_UPDATE
       splitterWindowSetMinimumPaneSize s 20
       splitterWindowSetSashSize s 5

       -- initialize tree control
       t <- treeCtrlCreate2 s idAny rectNull wxTR_HAS_BUTTONS
       treeCtrlAssignImageList t images  {- 'assign' deletes the imagelist on delete -}
       
       -- set top node
       top <- treeCtrlAddRoot t "System" (imageIndex imgComputer) imageNone objectNull
       treeCtrlSetItemPath t top ""

       -- add root directory
       (rootPath,rootName) <- getRootDir        
       root <- treeCtrlAppendItem t top rootName (imageIndex imgDisk) imageNone objectNull 
       treeCtrlSetItemPath t root rootPath 
       treeCtrlAddSubDirs t root

       -- expand top node
       treeCtrlExpand t top

       -- list control
       l  <- listCtrlCreate s idAny rectNull wxLC_REPORT
       listCtrlSetImageList l images wxIMAGE_LIST_SMALL
       listCtrlInsertColumn l 0 "Name" wxLIST_FORMAT_LEFT 140
       listCtrlInsertColumn l 1 "Permissions" wxLIST_FORMAT_LEFT 80
       listCtrlInsertColumn l 2 "Date" wxLIST_FORMAT_LEFT 100

       -- status bar
       status <- statusField []

       -- install event handlers
       treeCtrlOnTreeEvent t (onTreeEvent t l status)
       listCtrlOnListEvent l (onListEvent l t status)

       -- specify layout
       set f [layout     := container p $ margin 5 $ 
                            fill  $ widget s
             ,statusBar  := [status]
             ,clientSize := sz 500 300
             ]
       
       ssize <- get s clientSize
       splitterWindowSplitVertically s t l ((sizeW ssize) `div` 3)

       return ()


{--------------------------------------------------------------------------------

--------------------------------------------------------------------------------}
imageListAddIconsFromFiles images fnames
  = mapM_ (imageListAddIconFromFile images) fnames

imageListAddIconFromFile images fname
  = do icon <- iconCreateLoad fname (imageTypeFromFileName fname) (sz 16 16)
       imageListAddIcon images icon
       iconDelete icon
       return ()

{--------------------------------------------------------------------------------
   On tree event
--------------------------------------------------------------------------------}
onTreeEvent :: TreeCtrl a -> ListCtrl b -> StatusField -> EventTree -> IO ()
onTreeEvent t l status event
  = case event of
      TreeItemExpanding item veto
        -> do wxcBeginBusyCursor
              treeCtrlChildrenAddSubDirs t item
              wxcEndBusyCursor
              propagateEvent
      TreeSelChanged item olditem
        -> do wxcBeginBusyCursor
              path <- treeCtrlGetItemPath t item
              set status [text := path]
              listCtrlShowDir l path
              wxcEndBusyCursor
              propagateEvent
      other
        -> propagateEvent

onListEvent :: ListCtrl a -> TreeCtrl b -> StatusField -> EventList -> IO ()
onListEvent l t status event
  = case event of
      ListItemSelected item
        -> do fpath <- treeCtrlGetSelection t >>= treeCtrlGetItemPath t
              fname <- listCtrlGetItemText l item
              set status [text := fpath ++ fname]
              propagateEvent
      other
        -> propagateEvent
  
{--------------------------------------------------------------------------------
   View directory files
--------------------------------------------------------------------------------}
listCtrlShowDir :: ListCtrl a -> FilePath -> IO ()
listCtrlShowDir listCtrl path
  = do listCtrlDeleteAllItems listCtrl
       contents <- getDirectoryContents path
       let paths = map (\dir -> path ++ dir ++ "/") contents
       mapM_ (listCtrlAddFile listCtrl) (zip3 [0..] contents paths)
  `catch` \err -> return ()

listCtrlAddFile l (idx,fname,fpath)
  = do isdir <- doesDirectoryExist fpath `catch` \err -> return False
       perm  <- if isdir
                 then return (Permissions False False False False)
                 else getPermissions fpath
       time  <- getModificationTime fpath
       let image = imageIndex (if isdir 
                                then imgFolder 
                                else if (extension fname == "hs")
                                      then imgHFile
                                      else imgFile)
       listCtrlInsertItemWithLabel l idx fpath image
       listCtrlSetItem l idx 0 {- name -} fname image
       listCtrlSetItem l idx 1 {- perm -} (showPerm perm) imageNone
       listCtrlSetItem l idx 2 {- date -} (show time) imageNone

extension fname
  | elem '.' fname  = reverse (takeWhile (/='.') (reverse fname))
  | otherwise       = ""

showPerm perm
  = [if readable perm then 'r' else '-'
    ,if writable perm then 'w' else '-'
    ,if executable perm then 'x' else '-'
    ,if searchable perm then 's' else '-'
    ]

{--------------------------------------------------------------------------------
   Directory tree helpers
--------------------------------------------------------------------------------}
treeCtrlChildrenAddSubDirs :: TreeCtrl a -> TreeItem -> IO ()
treeCtrlChildrenAddSubDirs t parent
  = do children <- treeCtrlGetChildren t parent
       mapM_ (treeCtrlAddSubDirs t) children

treeCtrlAddSubDirs :: TreeCtrl a -> TreeItem -> IO ()
treeCtrlAddSubDirs t parent
  = do fpath <- treeCtrlGetItemPath t parent
       dirs  <- getSubdirs fpath
       treeCtrlDeleteChildren t parent
       mapM_ addChild dirs
       treeCtrlSetItemHasChildren t parent (not (null dirs))
  where
    addChild (path,name)
      = do item <- treeCtrlAppendItem t parent name (imageIndex imgFolder) (imageIndex imgFolderOpen) objectNull
           treeCtrlSetItemPath t item path


-- Return the sub directories of a certain directory as a tuple: the full path and the directory name.
getSubdirs :: FilePath -> IO [(FilePath,FilePath)]
getSubdirs fpath
  = do contents  <- getDirectoryContents fpath `catch` \err -> return []
       let names = filter (\dir -> head dir /= '.') contents
           paths = map (\dir -> fpath ++ dir ++ "/") names
       isdirs    <- mapM (\dir -> doesDirectoryExist dir `catch` \err -> return False) paths
       let dirs  = [(path,name) | (isdir,(path,name)) <- zip isdirs (zip paths names), isdir]
       return dirs
       

-- Return the root directory as a tuple: the full path and name.
getRootDir :: IO (FilePath,FilePath)
getRootDir
  = do current <- getCurrentDirectory
       let isDirSep c = (c == '\\' || c == '/')
           rootName  = takeWhile (not . isDirSep) current
           rootPath  = rootName ++ "/"
       exist <- do{ getDirectoryContents rootPath; return True } `catch` \err -> return False
       if exist
        then return (rootPath,rootName)
        else return (current ++ "/", reverse (takeWhile (not . isDirSep) (reverse current)))
