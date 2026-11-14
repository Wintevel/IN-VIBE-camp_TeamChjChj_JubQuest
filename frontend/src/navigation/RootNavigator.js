import { createBottomTabNavigator } from '@react-navigation/bottom-tabs'
import { DarkTheme, NavigationContainer } from '@react-navigation/native'
import { createNativeStackNavigator } from '@react-navigation/native-stack'
import { Text, View } from 'react-native'
import { TabIcon } from '../components/Icons'
import { navigationRef } from './ref'
import { useApp } from '../state/AppState'
import { colors, text } from '../theme'
import BoardScreen from '../screens/BoardScreen'
import CaptureScreen from '../screens/CaptureScreen'
import CollectionScreen from '../screens/CollectionScreen'
import CrewScreen from '../screens/CrewScreen'
import HelpScreen from '../screens/HelpScreen'
import LoginScreen from '../screens/LoginScreen'
import MapScreen from '../screens/MapScreen'
import NoticesScreen from '../screens/NoticesScreen'
import MeScreen from '../screens/MeScreen'
import ProofScreen from '../screens/ProofScreen'
import ReportCreateScreen from '../screens/ReportCreateScreen'
import ShopScreen from '../screens/ShopScreen'
import StylePickScreen from '../screens/StylePickScreen'
import StyleScreen from '../screens/StyleScreen'
import VaultScreen from '../screens/VaultScreen'
import SettingsScreen from '../screens/SettingsScreen'
import TutorialScreen from '../screens/TutorialScreen'

const Tab = createBottomTabNavigator()
const Stack = createNativeStackNavigator()

const theme = { ...DarkTheme, colors: { ...DarkTheme.colors, background: colors.ink, card: colors.ink, border: colors.line, text: colors.fg, primary: colors.blue } }

const TABS = [
  ['Board', BoardScreen, '의뢰판', 'board'],
  ['Map', MapScreen, '지도', 'map'],
  ['Crew', CrewScreen, '크루', 'crew'],
  ['Me', MeScreen, '내 정보', 'me'],
]

function Tabs() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.fg,
        tabBarInactiveTintColor: colors.disabled,
        tabBarStyle: { backgroundColor: colors.ink, borderTopColor: colors.line },
        tabBarLabel: ({ children, color }) => <Text style={[text.tab, { color }]}>{children}</Text>,
      }}
    >
      {TABS.map(([name, component, title, icon]) => (
        <Tab.Screen key={name} name={name} component={component} options={{ title, tabBarIcon: ({ color }) => <TabIcon name={icon} color={color} /> }} />
      ))}
    </Tab.Navigator>
  )
}

// 화면을 넘길 때 오른쪽에서 짧게 밀려 들어옵니다(폰). 웹은 components/Screen.js 의 등장 움직임이 대신합니다.
const stackScreen = { headerShown: false, contentStyle: { backgroundColor: colors.ink }, animation: 'slide_from_right', animationDuration: 220 }

export default function RootNavigator() {
  const { session, tutorialSeen } = useApp()
  if (session === undefined || tutorialSeen === undefined) return <View style={{ flex: 1, backgroundColor: colors.ink }} />
  const signedIn = !!session
  return (
    <NavigationContainer theme={theme} ref={navigationRef}>
      <Stack.Navigator screenOptions={stackScreen}>
        {signedIn && !tutorialSeen ? (
          <Stack.Screen name="Tutorial" component={TutorialScreen} />
        ) : signedIn ? (
          <>
            <Stack.Screen name="Main" component={Tabs} />
            <Stack.Screen name="ReportCreate" component={ReportCreateScreen} options={{ presentation: 'modal' }} />
            <Stack.Screen name="Capture" component={CaptureScreen} options={{ presentation: 'fullScreenModal' }} />
            <Stack.Screen name="Settings" component={SettingsScreen} />
            <Stack.Screen name="Shop" component={ShopScreen} />
            <Stack.Screen name="Style" component={StyleScreen} />
            <Stack.Screen name="StylePick" component={StylePickScreen} />
            <Stack.Screen name="Collection" component={CollectionScreen} />
            <Stack.Screen name="Vault" component={VaultScreen} />
            <Stack.Screen name="Help" component={HelpScreen} />
            <Stack.Screen name="Proof" component={ProofScreen} />
            <Stack.Screen name="Notices" component={NoticesScreen} />
          </>
        ) : (
          <Stack.Screen name="Login" component={LoginScreen} />
        )}
      </Stack.Navigator>
    </NavigationContainer>
  )
}
