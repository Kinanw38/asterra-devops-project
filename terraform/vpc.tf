# יצירת ה-VPC המרכזי של הפרויקט - מבודד ומנוהל
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true # קריטי כדי לאפשר למכונות ול-RDS לקבל כתובות DNS פנימיות תקינות
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

# רכיב גישת אינטרנט עבור הרכיבים הציבוריים בשכבת ה-Frontend
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.environment}-igw" }
}

# סאבנטים ציבוריים - מיועדים לרכיבים שחייבים גישה ישירה מהעולם (כמו אתר הוורדפרס)
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true # מקצה IP ציבורי אוטומטית למכונות בשכבה זו
  tags                    = { Name = "${var.environment}-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.environment}-public-2" }
}

# סאבנטים פרטיים - מבודדים לחלוטין לצורך הגנה על בסיס הנתונים ושירותי עיבוד המידע
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}a"
  tags              = { Name = "${var.environment}-private-1" }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = { Name = "${var.environment}-private-2" }
}

# הקצאת IP סטטי (Elastic IP) עבור ה-NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.environment}-nat-eip" }
}

# יצירת NAT Gateway בסאבנט הציבורי - מאפשר למכונות הפרטיות ליזום יציאה לאינטרנט (למשל לצורך עדכוני חבילות) מבלי להיחשף לעולם
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id
  tags          = { Name = "${var.environment}-nat-gw" }
}

# טבלאות ניתוב (Route Tables) לקביעת זרימת התעבורה ברשת
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.environment}-public-rt" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.environment}-private-rt" }
}

# שיוך הסאבנטים לטבלאות הניתוב המתאימות להחלת הכללים ברמת התשתית
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}