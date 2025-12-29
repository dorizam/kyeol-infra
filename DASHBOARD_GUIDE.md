# Saleor Dashboard 사용 가이드

Saleor Dashboard에서 상품을 등록하고 주문을 받기 위한 설정 가이드입니다.

---

## 1. 상품 등록

1. **Catalog** → **Products** → **Create Product** 클릭
2. **Product Type**: `Default Type` 선택
3. **General Information** 입력:
   - Name (상품명)
   - Description (설명)
4. **Shipping** 섹션:
   - Weight (무게)
5. **Pricing** 섹션:
   - Price (가격)
6. **Inventory** 섹션:
   - SKU (재고 관리 코드)
7. **Organize Products** (우측):
   - Product Type: `Default Type`
   - Category: `Default Category`
8. **Availability** 섹션:
   - ✅ `Default Channel` 체크 확인
   - **Published** 클릭
9. 우측 하단 **Save** 클릭
10. 이미지 등록 (선택사항) 후 **Save** 클릭

---

## 2. 메인 페이지 상품 노출 (Featured Products)

> ⚠️ 이 설정이 없으면 Storefront 메인 페이지에 상품이 표시되지 않습니다!

1. **Catalog** → **Collections** → **Create Collection** 클릭
2. **Name**: `Featured Products` 입력 (정확히 이 이름 사용!)
3. 우측 **Default Channel** 토글 열기:
   - ✅ **Visible** 체크
4. 우측 하단 **Save** 클릭
5. 저장 후 하단 **Products in Featured Products** 섹션:
   - **Assign Products** 클릭
   - 노출시킬 상품 선택 → **Assign** 클릭

---

## 3. 결제 설정 (필수!)

> ⚠️ 이 설정이 없으면 주문이 생성되지 않습니다!

1. **Configuration** → **Channels** → **Default Channel** 클릭
2. **Checkout Settings** 섹션:
   - ✅ **Allow unpaid orders** 체크
3. **Save** 클릭

---

## 4. 계정 생성 및 주문 (Storefront)

### 4.1 주문 프로세스

1. Storefront에서 **상품 1개 이상** 장바구니에 담기
2. **Checkout** 진행
3. **Create Account** 체크박스 체크 + 비밀번호 입력 (회원가입)
4. 배송 주소 입력

### 4.2 테스트용 미국 주소 예시

```
Street address: 4300 GLENNS RD
Street address (continue): 789789
City: GLOUCESTER
Zip code: 23061-2734
State: Virginia
```

### 4.3 결제 완료

- **Payment methods** 섹션에서 **Make payment and create order** 클릭
- 계정 생성 → 주문 생성 순서로 처리됨
- 이후 해당 이메일/비밀번호로 로그인 가능

---

## 📋 체크리스트

| 항목 | 확인 |
|------|------|
| 상품 등록 및 Published | ☐ |
| Featured Products Collection 생성 | ☐ |
| Collection에 상품 할당 | ☐ |
| Allow unpaid orders 설정 | ☐ |
