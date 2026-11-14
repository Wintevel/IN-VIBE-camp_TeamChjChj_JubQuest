import { useEffect, useRef } from 'react'
import { Animated, Easing, ScrollView, StyleSheet } from 'react-native'
import { useIsFocused } from '@react-navigation/native'
import { useSafeAreaInsets } from 'react-native-safe-area-context'
import BoardBackground from './BoardBackground'
import { ND, reduced } from './Motion'

// 탭·스택 화면 공통 틀: 게시판 배경 + 안전영역 + 좌우 20 패딩
export default function Screen({ children, top = true, bottomPad = 24, refreshControl }) {
  const insets = useSafeAreaInsets()
  // 화면에 들어올 때마다 내용이 오른쪽에서 짧게 미끄러져 들어옵니다(탭 전환, 다른 화면에서 돌아올 때 포함).
  const focused = useIsFocused()
  const v = useRef(new Animated.Value(reduced() ? 1 : 0)).current
  useEffect(() => {
    if (!focused || reduced()) return
    v.setValue(0)
    Animated.timing(v, { toValue: 1, duration: 220, easing: Easing.out(Easing.cubic), useNativeDriver: ND }).start()
  }, [focused, v])
  return (
    <BoardBackground>
      <Animated.View style={{ flex: 1, opacity: v, transform: [{ translateX: v.interpolate({ inputRange: [0, 1], outputRange: [18, 0] }) }] }}>
      <ScrollView refreshControl={refreshControl} contentContainerStyle={[styles.content, { paddingTop: (top ? insets.top : 0) + 8, paddingBottom: bottomPad }]} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        {children}
      </ScrollView>
      </Animated.View>
    </BoardBackground>
  )
}

const styles = StyleSheet.create({ content: { paddingHorizontal: 20, gap: 16 } })
