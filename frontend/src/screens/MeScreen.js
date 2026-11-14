import { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import Svg, { Circle, Line, Path, Text as SvgText } from "react-native-svg";
import AvatarFrame from "../components/AvatarFrame";
import DailyLimits from "../components/DailyLimits";
import {
  BackpackIcon,
  BadgeIcon,
  GearIcon,
  HelpIcon,
  PointIcon,
  XpIcon,
} from "../components/Icons";
import { Appear, Bar, CountUp, PressScale } from "../components/Motion";
import { Card, List, SectionTitle } from "../components/ListRows";
import ReportCard from "../components/ReportCard";
import Screen from "../components/Screen";
import { Empty, Loading, refresher } from "../components/States";
import {
  progress,
  statsOf,
  titleText,
} from "../lib/achievements";
import { useApp } from "../state/AppState";
import { colors, font, radius, text } from "../theme";

const day = (t) => {
  const d = new Date(t);
  return `${d.getMonth() + 1}월 ${d.getDate()}일`;
};

export default function MeScreen({ navigation }) {
  const app = useApp();
  const p = app.profile;
  if (!p) {
    return (
      <Screen refreshControl={refresher(app)}>
        {app.loading ? (
          <Loading />
        ) : (
          <Empty
            title="내 정보를 불러오지 못했어요"
            action="다시 시도"
            onAction={() => app.refresh()}
          />
        )}
      </Screen>
    );
  }
  const progress01 = p.xp_for_next_level
    ? Math.min(1, (p.xp_in_level || 0) / p.xp_for_next_level)
    : 0;
  const mine = app.reports.filter(
    (r) => r.i_am_participating && r.status !== "completed",
  );
  const s = statsOf(p, app.myCrew);
  const feats = progress(s, p.feats_claimed || []);
  const ready = feats.filter((a) => a.done && !a.claimed).length;
  const weekly = p.weekly || [];
  // 오른쪽 끝에서부터 이어진 주가 연속 활동 구간입니다.
  const streakLen =
    (p.streak_weeks || 0) + (weekly[weekly.length - 1] ? 0 : 1);
  const vault = (p.coupons || []).length + (p.rewards || []).length;
  const waiting = app.notices.filter((n) => !n.answer).length;
  const title = titleText(p, app.myCrew);
  return (
    <Screen refreshControl={refresher(app)}>
      <View style={styles.me}>
        <View style={{ alignItems: "center", gap: 8 }}>
          <AvatarFrame
            frame={p.frame}
            size={64}
            letter={(p.nickname || "줍").slice(0, 1)}
            uri={p.avatar_url}
          />
          {app.canStyle ? (
            <Pressable
              onPress={() => navigation.navigate("Style")}
              accessibilityRole="button"
              accessibilityLabel="프로필 꾸미기 열기"
              style={styles.chip}
            >
              <Text style={[text.chip, { color: colors.fg }]}>꾸미기</Text>
            </Pressable>
          ) : null}
        </View>
        <View style={{ flex: 1, alignSelf: "flex-start", paddingTop: 8 }}>
          <Text style={[text.cardTitle, { fontSize: 20 }]}>
            <Text style={p.name_color && { color: p.name_color }}>
              {p.nickname}
            </Text>
            {title ? (
              <Text style={[text.chip, { color: colors.tape }]}>
                {" · "}
                {title}
              </Text>
            ) : null}
          </Text>
          <Text style={[text.small, { marginTop: 4 }]}>
            {app.myCrew ? app.myCrew.name : "크루 없음"}
          </Text>
        </View>
        <Pressable
          onPress={() => navigation.navigate("Settings")}
          accessibilityRole="button"
          accessibilityLabel="설정"
          style={[styles.chip, { alignSelf: "flex-start", marginTop: 6 }]}
        >
          <GearIcon size={15} />
          <Text style={[text.chip, { color: colors.fg }]}>설정</Text>
        </Pressable>
      </View>

      {app.guest ? (
        <Pressable
          onPress={() => app.signOut()}
          accessibilityRole="button"
          style={styles.guest}
        >
          <Text style={[text.small, { flex: 1, color: colors.fg }]}>
            둘러보는 중이에요. 제보·하트·의뢰 해결은 로그인한 뒤에 할 수
            있어요.
          </Text>
          <Text style={[text.chip, { color: colors.blue }]}>로그인</Text>
        </Pressable>
      ) : null}

      <Card style={{ gap: 8 }}>
        <View style={styles.row}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <XpIcon size={18} />
            <Text style={text.small}>레벨</Text>
          </View>
          <Text style={text.num}>Lv.{p.level}</Text>
        </View>
        <Bar ratio={progress01} color={colors.blue} track={colors.panel2} />
        <View style={styles.row}>
          <Text style={text.small}>
            다음 레벨까지{" "}
            {Math.max(0, (p.xp_for_next_level || 0) - (p.xp_in_level || 0))}XP
          </Text>
          <Text style={text.small}>누적 {(p.xp || 0).toLocaleString()}XP</Text>
        </View>
      </Card>

      <Appear from="left">
        <View style={styles.wallet}>
          <View style={styles.slash} />
          <View style={styles.slash2} />
          <PointIcon size={30} />
          <View style={{ flex: 1 }}>
            <Text style={text.caption}>내 포인트</Text>
            <CountUp
              value={p.points || 0}
              style={[
                text.point,
                { fontSize: 26, lineHeight: 30, color: colors.tape },
              ]}
            />
          </View>
          <PressScale
            onPress={() => navigation.navigate("Shop")}
            accessibilityRole="button"
            accessibilityLabel="포인트 교환 상점 열기"
            style={styles.shopBtn}
          >
            <Text style={[text.chip, { color: colors.tapeInk }]}>교환 상점</Text>
          </PressScale>
        </View>
      </Appear>

      <Appear from="left" index={1}>
        <PressScale
          onPress={() => navigation.navigate("Collection")}
          accessibilityRole="button"
          accessibilityLabel="도전과제 열기"
          style={styles.feats}
        >
          <BadgeIcon size={24} />
          <View style={{ flex: 1 }}>
            <Text style={[text.chip, { color: colors.purple }]}>도전과제</Text>
            <Text style={[text.small, { marginTop: 2 }]}>
              {feats.filter((a) => a.done).length}/{feats.length} 달성
            </Text>
          </View>
          {ready > 0 ? (
            <View style={styles.ready}>
              <Text style={[text.chip, { color: "#fff" }]}>
                받을 보상 {ready}개
              </Text>
            </View>
          ) : (
            <Text style={[text.small, { color: colors.sub }]}>보기</Text>
          )}
        </PressScale>
      </Appear>

      <SectionTitle>내 활동</SectionTitle>
      <Card style={{ gap: 14 }}>
        <View style={{ flexDirection: "row" }}>
          {[
            [p.completed_count || 0, "건", "완료한 의뢰"],
            [p.streak_weeks || 0, "주", "연속 활동"],
            [weekly[weekly.length - 1] || 0, "건", "이번 주"],
          ].map(([num, unit, label]) => (
            <View key={label} style={{ flex: 1 }}>
              <Text style={text.point}>
                {num}
                <Text style={[text.small, { color: colors.sub }]}> {unit}</Text>
              </Text>
              <Text style={[text.caption, { marginTop: 2 }]}>{label}</Text>
            </View>
          ))}
        </View>
        <WeekLine weekly={weekly} streak={streakLen} />
        <Text style={text.caption}>
          {p.streak_weeks > 0
            ? `초록 선이 이어진 ${p.streak_weeks}주예요. ${p.active_this_week ? "이번 주도 이어 갔어요" : "이번 주에 한 건만 해결하면 이어져요"}`
            : "한 주에 한 건만 해결해도 연속 활동이 시작돼요"}
        </Text>
      </Card>

      <SectionTitle>오늘 남은 횟수</SectionTitle>
      <DailyLimits profile={p} />

      <List
        rows={[
          {
            label: "보관함",
            icon: <BackpackIcon />,
            value: vault > 0 ? `쿠폰·제휴 보상 ${vault}개` : "쿠폰·제휴 보상",
            onPress: () => navigation.navigate("Vault"),
          },
        ]}
      />

      {p.cleaned?.length > 0 ? (
        <>
          <SectionTitle>내가 치운 곳</SectionTitle>
          <List
            rows={p.cleaned
              .slice(0, 10)
              .map((c) => ({
                label: c.title,
                value: [c.place_label, day(c.at)].filter(Boolean).join(" · "),
                key: `${c.id}-${c.at}`,
              }))}
          />
        </>
      ) : null}

      <SectionTitle>진행 중인 내 의뢰</SectionTitle>
      <View style={{ gap: 14 }}>
        {mine.map((r) => (
          <ReportCard
            key={r.id}
            report={r}
            onPress={() => app.openSheet(r.id)}
            onHeart={() => app.toggleHeart(r.id)}
          />
        ))}
        {mine.length === 0 ? (
          <List
            rows={[
              {
                label: "수락한 의뢰가 없어요",
                value: "의뢰판에서 골라 보세요",
                onPress: () => navigation.navigate("Board"),
              },
            ]}
          />
        ) : null}
      </View>

      <List
        rows={[
          ...(app.social
            ? [
                {
                  label: "해결 확인",
                  value: `${waiting}건 대기`,
                  onPress: () => navigation.navigate("Notices"),
                },
              ]
            : []),
          {
            label: "도움말",
            icon: <HelpIcon />,
            value: "쓰는 법과 규칙",
            onPress: () => navigation.navigate("Help"),
          },
        ]}
      />
    </Screen>
  );
}

// 최근 8주 해결 수를 선으로 그립니다. 연속 활동 구간은 초록입니다.
function WeekLine({ weekly, streak }) {
  const [w, setW] = useState(0);
  const H = 132;
  const top = Math.max(1, ...weekly);
  const n = weekly.length;
  const padX = 18;
  const x = (i) => padX + (n > 1 ? (i * (w - padX * 2)) / (n - 1) : 0);
  const y = (v) => 24 + (1 - v / top) * (H - 24 - 26);
  const first = Math.max(0, n - streak);
  const seg = (from, to) =>
    weekly
      .slice(from, to + 1)
      .map((v, k) => `${k ? "L" : "M"}${x(from + k)} ${y(v)}`)
      .join("");
  const label = (i) =>
    i === n - 1 ? "이번주" : i === n - 2 ? "지난주" : `${n - 1 - i}주 전`;
  return (
    <View
      style={{ height: H }}
      onLayout={(e) => setW(e.nativeEvent.layout.width)}
      accessibilityRole="image"
      accessibilityLabel={`최근 ${n}주 동안 주마다 해결한 수: ${weekly.join(", ")}`}
    >
      {w > 0 && n > 0 ? (
        <Svg width={w} height={H}>
          {[0, 0.5, 1].map((t) => (
            <Line
              key={t}
              x1={0}
              x2={w}
              y1={y(top * t)}
              y2={y(top * t)}
              stroke={colors.line}
              strokeWidth={1}
            />
          ))}
          <Path
            d={seg(0, n - 1)}
            stroke={colors.blue}
            strokeWidth={2.5}
            fill="none"
            strokeLinejoin="round"
            strokeLinecap="round"
          />
          {first < n - 1 ? (
            <Path
              d={seg(first, n - 1)}
              stroke={colors.green}
              strokeWidth={2.5}
              fill="none"
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          ) : null}
          {weekly.map((v, i) => {
            const on = i >= first && v > 0;
            return (
              <Circle
                key={i}
                cx={x(i)}
                cy={y(v)}
                r={4}
                fill={v === 0 ? colors.panel : on ? colors.green : colors.blue}
                stroke={on ? colors.green : v === 0 ? colors.sub : colors.blue}
                strokeWidth={2}
              />
            );
          })}
          {weekly.map((v, i) => (
            <SvgText
              key={`v${i}`}
              x={x(i)}
              y={y(v) - 9}
              fontSize={11}
              fontWeight="700"
              fill={v > 0 ? colors.fg : colors.disabled}
              textAnchor="middle"
            >
              {v}
            </SvgText>
          ))}
          {weekly.map((v, i) =>
            i % 2 === (n - 1) % 2 ? (
              <SvgText
                key={`l${i}`}
                x={x(i)}
                y={H - 4}
                fontSize={11}
                fill={i === n - 1 ? colors.fg : colors.sub}
                textAnchor={i === n - 1 ? "end" : "middle"}
                dx={i === n - 1 ? 14 : 0}
              >
                {label(i)}
              </SvgText>
            ) : null,
          )}
        </Svg>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  me: {
    flexDirection: "row",
    gap: 18,
    paddingLeft: 6,
    paddingTop: 6,
    alignItems: "center",
  },
  row: {
    flexDirection: "row",
    justifyContent: "space-between",
    alignItems: "center",
  },
  chip: {
    flexDirection: "row",
    alignItems: "center",
    gap: 5,
    backgroundColor: colors.panel2,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: radius.pill,
  },
  guest: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    padding: 14,
    borderRadius: radius.lg,
    backgroundColor: colors.blueWeak,
  },
  wallet: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    padding: 16,
    borderRadius: radius.lg,
    backgroundColor: colors.panel,
    borderWidth: 1,
    borderColor: colors.tape,
    overflow: "hidden",
  },
  slash: {
    position: "absolute",
    right: 110,
    top: -30,
    bottom: -30,
    width: 44,
    backgroundColor: "rgba(255,212,59,0.12)",
    transform: [{ skewX: "-18deg" }],
  },
  slash2: {
    position: "absolute",
    right: 168,
    top: -30,
    bottom: -30,
    width: 12,
    backgroundColor: "rgba(255,212,59,0.12)",
    transform: [{ skewX: "-18deg" }],
  },
  shopBtn: {
    backgroundColor: colors.tape,
    paddingHorizontal: 14,
    paddingVertical: 10,
    borderRadius: radius.pill,
  },
  feats: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    padding: 14,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.purple,
    backgroundColor: "rgba(169,124,255,0.08)",
  },
  ready: {
    backgroundColor: colors.purple,
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: radius.pill,
  },
});
