module StorageTest (tests) where

import Data.ByteString.Char8 (pack)
import Data.List ( sort )
import qualified Database.Persist.Sqlite as P
import DMSS.Storage
  ( storeCheckIn
  , storeUser
  , getUserKey
  , removeUser
  , listCheckIns
  )
import DMSS.Storage.TH
import DMSS.Storage.Types
  ( BoxKeypairStore (..)
  , CheckInProof (..)
  , Name (..)
  , PassHash (..)
  , Silent (..)
  , SignKeypairStore (..)
  , fromPassHash, hashPassword, toPassHash
  )
import Test.Tasty ( TestTree, testGroup )
import Test.Tasty.HUnit ( Assertion, (@?=), assertFailure, testCase )
import qualified Test.Tasty.QuickCheck as QC

import Common ( withTemporaryTestDirectory )


tests :: [TestTree]
tests =
  [ testCase "store_user_key_test" storeUserTest
  , testCase "store_check_in_test" storeCheckInTest
  , testCase "remove_user_key_test" removeUserKeyTest
  , toFromPassHash
  , QC.testProperty "prop_userStorage_BoxKeypairStore"
      prop_userStorage_BoxKeypairStore
  , QC.testProperty "prop_userStorage_SignKeypairStore"
      prop_userStorage_SignKeypairStore
  ]

tempDir :: FilePath
tempDir = "storageTest"


dummyPassHash :: PassHash
dummyPassHash = PassHash . pack $ "$argon2id$v=19$m=1048576,t=4,p=1$p4S9shWCYwIX1zTKxWrblQ$nJx1a6Yg3jJwvP+d8nBU+dkFYqM3LlnfhMh01OMbD4Q\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL\NUL"


dummyBoxKeypairStore :: BoxKeypairStore
dummyBoxKeypairStore = BoxKeypairStore (pack "Box encryptedPrivateKeyCiphertext") (pack "Box publicKeyText")
dummySignKeypairStore :: SignKeypairStore
dummySignKeypairStore = SignKeypairStore (pack "Sign encryptedPrivateKeyCiphertext") (pack "Sign publicKeyText")

storeUserTest :: Assertion
storeUserTest = withTemporaryTestDirectory tempDir ( \_ -> do
    -- Store fake user key
    let n = Name "joe"
    _ <- storeUser n dummyPassHash dummyBoxKeypairStore dummySignKeypairStore

    -- Check that the fake user key was stored
    k <- getUserKey (Silent True) n
    case k of
      Nothing -> assertFailure $ "Could not find User based on (" ++ (unName n) ++ ")"
      _       -> return ()
  )

removeUserKeyTest :: Assertion
removeUserKeyTest = withTemporaryTestDirectory tempDir ( \_ -> do
    -- Store fake user key
    let n = Name "deleteMe1234"
    _ <- storeUser n dummyPassHash dummyBoxKeypairStore dummySignKeypairStore

    -- Remove key
    removeUser n

    -- Check that the fake user key was stored
    k <- getUserKey (Silent True) n
    case k of
      Nothing -> return ()
      _       -> assertFailure $ "Found UserKey based on (" ++ (unName n) ++ ") but shouldn't have"
  )

storeCheckInTest :: Assertion
storeCheckInTest = withTemporaryTestDirectory tempDir ( \_ -> do
    -- Store a checkin
    let n = Name "joe"
    _ <- storeUser n dummyPassHash dummyBoxKeypairStore dummySignKeypairStore
    res <- storeCheckIn n (CheckInProof "MyProof")
    case res of
      (Left s) -> assertFailure s
      _ -> return ()
    -- Get a list of checkins
    l <- listCheckIns n 10
    -- Verify that only one checkin was returned
    case l of
      (_:[])    -> return ()
      x         -> assertFailure $ "Did not find one checkin: " ++ show x

    -- Create another checkin and verify order is correct
    _ <- storeCheckIn n (CheckInProof "More proof")
    _ <- storeCheckIn n (CheckInProof "Even more proof")
    l' <- listCheckIns n 10
    let createdList = map (\x -> checkInCreated $ P.entityVal x) l'
    if createdList == (reverse . sort) createdList
      then return ()
      else assertFailure "CheckIns were not in decending order"
  )


toFromPassHash :: TestTree
toFromPassHash = testGroup "Round-trip between PasswordString and PassHash"
  [ tc ("A short, awful password",  "foobar")
  , tc ("A decent password",        "c%fxBQRe]2L]|#q'")
  , tc ("A passphrase",             "obese page rivet gurgle ring twin usia befit olsen")
  ]

  where
    tc (desc, password) =
      testCase desc $ (toPassHash <$> fromPassHash ph) @?= (Right ph)
      where ph = hashPassword password


-- Ensure data that goes into Persistence comes out the same
prop_userStorage_BoxKeypairStore :: BoxKeypairStore -> Bool
prop_userStorage_BoxKeypairStore bkp =
  (Right bkp) == (P.fromPersistValue . P.toPersistValue) bkp

prop_userStorage_SignKeypairStore :: SignKeypairStore -> Bool
prop_userStorage_SignKeypairStore bkp =
  (Right bkp) == (P.fromPersistValue . P.toPersistValue) bkp
