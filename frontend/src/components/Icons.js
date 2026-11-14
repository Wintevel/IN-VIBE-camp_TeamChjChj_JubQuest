import Svg, { Circle, Path, Rect } from 'react-native-svg'
import { colors } from '../theme'

const base = { fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round' }

export function TabIcon({ name, color, size = 24 }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      {name === 'board' && (
        <>
          <Rect x="4" y="3" width="16" height="18" rx="3" {...p} />
          <Path d="M8 8h8M8 12h8M8 16h5" {...p} />
        </>
      )}
      {name === 'map' && (
        <>
          <Path d="M9 4 3 6v14l6-2 6 2 6-2V4l-6 2-6-2Z" {...p} />
          <Path d="M9 4v14M15 6v14" {...p} />
        </>
      )}
      {name === 'crew' && (
        <>
          <Path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0V4Z" {...p} />
          <Path d="M7 6H4a3 3 0 0 0 3 4M17 6h3a3 3 0 0 1-3 4" {...p} />
        </>
      )}
      {name === 'me' && (
        <>
          <Circle cx="12" cy="8" r="4" {...p} />
          <Path d="M4 21a8 8 0 0 1 16 0" {...p} />
        </>
      )}
    </Svg>
  )
}

export function HeartIcon({ filled, color, size = 18 }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path
        d="M12 21s-7.5-4.6-9.5-9.2C1.2 8.7 3 5.5 6.2 5.5c2 0 3.4 1.1 4.3 2.4l1.5 1.9 1.5-1.9c.9-1.3 2.3-2.4 4.3-2.4 3.2 0 5 3.2 3.7 6.3C19.5 16.4 12 21 12 21Z"
        {...base}
        stroke={color}
        fill={filled ? color : 'none'}
      />
    </Svg>
  )
}

// 보상 아이콘: 포인트(노란 동전) · 내 경험치(파란 마름모 번개) · 크루 활동 경험치(보라 방패) · 제휴 보상(선물)
export function PointIcon({ size = 18 }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Circle cx="12" cy="12" r="11" fill={colors.tape} />
      <Circle cx="12" cy="12" r="8" fill="none" stroke={colors.tapeInk} strokeOpacity="0.25" strokeWidth="1.5" />
      <Path d="M9.6 17V7.2h3.1a2.9 2.9 0 0 1 0 5.8H9.6" fill="none" stroke={colors.tapeInk} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  )
}

export function XpIcon({ size = 18 }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M12 1 23 12 12 23 1 12Z" fill={colors.blue} />
      <Path d="M13.2 5.5 8 13h3.4l-.8 5.5L16 11h-3.5l.7-5.5Z" fill="#fff" />
    </Svg>
  )
}

export function CrewXpIcon({ size = 18 }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M12 1.5 21 5v6.5c0 5-3.6 9-9 11-5.4-2-9-6-9-11V5l9-3.5Z" fill={colors.purple} />
      <Path d="m7.8 12 4.2-4 4.2 4M7.8 16.5l4.2-4 4.2 4" fill="none" stroke="#fff" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
    </Svg>
  )
}

export function GiftIcon({ size = 18, color = colors.tape }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Rect x="3" y="8" width="18" height="5" rx="1.5" {...p} />
      <Path d="M5 13v8h14v-8M12 8v13M12 8S10.5 3 8 3a2.5 2.5 0 0 0 0 5h4Zm0 0s1.5-5 4-5a2.5 2.5 0 0 1 0 5h-4Z" {...p} />
    </Svg>
  )
}

export function CameraIcon({ size = 22, color = colors.sub }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z" {...p} />
      <Circle cx="12" cy="13.5" r="3.5" {...p} />
    </Svg>
  )
}

export function PinIcon({ size = 22, color = colors.disabled }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M12 21s7-6.2 7-11.5a7 7 0 0 0-14 0C5 14.8 12 21 12 21Z" {...p} />
      <Circle cx="12" cy="9.5" r="2.5" {...p} />
    </Svg>
  )
}

// 도전과제·도감: 리본 달린 별 메달(보라)
export function BadgeIcon({ size = 18, color = colors.purple }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M8 13.5 6 22l6-3 6 3-2-8.5" fill={color} opacity={0.55} />
      <Circle cx={12} cy={9.5} r={7.5} fill={color} />
      <Path d="M12 5.2l1.4 2.9 3.1.4-2.3 2.2.6 3.1-2.8-1.5-2.8 1.5.6-3.1-2.3-2.2 3.1-.4z" fill={colors.ink} />
    </Svg>
  )
}

// 설정 톱니바퀴
export function GearIcon({ size = 16, color = colors.fg }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Circle cx="12" cy="12" r="6.2" {...p} />
      <Circle cx="12" cy="12" r="2.2" {...p} />
      {[0, 45, 90, 135, 180, 225, 270, 315].map((deg) => {
        const a = (deg * Math.PI) / 180
        return <Path key={deg} d={`M${12 + Math.cos(a) * 7.6} ${12 + Math.sin(a) * 7.6}L${12 + Math.cos(a) * 10} ${12 + Math.sin(a) * 10}`} {...p} strokeWidth={3} />
      })}
    </Svg>
  )
}

// 잠금 자물쇠
export function LockIcon({ size = 12, color = colors.fg }) {
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M8 11V8a4 4 0 0 1 8 0v3" fill="none" stroke={color} strokeWidth={2.6} strokeLinecap="round" />
      <Rect x="5" y="10.5" width="14" height="10.5" rx="2.5" fill={color} />
    </Svg>
  )
}

// 보관함: 배낭
export function BackpackIcon({ size = 20, color = colors.tape }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Path d="M9 6V5a3 3 0 0 1 6 0v1" {...p} />
      <Path d="M6 21h12a1.5 1.5 0 0 0 1.5-1.5V11A5 5 0 0 0 14.5 6h-5A5 5 0 0 0 4.500 11v8.5A1.5 1.5 0 0 0 6 21z" {...p} />
      <Path d="M8.500 21v-5.500h7V21M8.500 11h7" {...p} />
    </Svg>
  )
}

// 도움말: 동그라미 안 물음표
export function HelpIcon({ size = 20, color = colors.blue }) {
  const p = { ...base, stroke: color }
  return (
    <Svg width={size} height={size} viewBox="0 0 24 24">
      <Circle cx="12" cy="12" r="9" {...p} />
      <Path d="M9.300 9.300a2.800 2.800 0 1 1 4.200 2.400c-.900.600-1.500 1.100-1.500 2.300" {...p} />
      <Circle cx="12" cy="17.200" r="1.100" fill={color} />
    </Svg>
  )
}
